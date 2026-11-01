-- Security/runtime baseline for isolated Staging. No production rows or secrets are copied.
-- Push delivery and Vault-backed VAPID functions are intentionally excluded.
set search_path=public,extensions,auth;
create schema if not exists private;

CREATE OR REPLACE FUNCTION private.exchange_review_is_published(p_proposal_id uuid, p_reviewer_id uuid, p_reviewed_user_id uuid, p_created_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    p_created_at <= now() - interval '24 hours'
    or exists (
      select 1
      from public.exchange_reviews reciprocal
      where reciprocal.proposal_id = p_proposal_id
        and reciprocal.reviewer_id = p_reviewed_user_id
        and reciprocal.reviewed_user_id = p_reviewer_id
    );
$function$;

CREATE OR REPLACE FUNCTION private.invite_business_team_member(p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_owner uuid := auth.uid();
  v_member uuid;
  v_membership uuid;
  v_email text := lower(trim(coalesce(p_email,'')));
  v_owner_name text;
  v_count integer;
begin
  if v_owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if length(v_email)<5 or position('@' in v_email)<2 then raise exception 'Введите корректный email' using errcode='22023'; end if;
  if not exists(select 1 from public.user_subscriptions us where us.user_id=v_owner and us.plan_code='business' and us.status='active' and us.starts_at<=now() and us.ends_at>now()) then
    raise exception 'Для командного доступа нужен активный тариф Business' using errcode='42501';
  end if;
  select u.id into v_member from auth.users u where lower(u.email)=v_email limit 1;
  if v_member is null then raise exception 'Пользователь с таким email ещё не зарегистрирован в ПО БАРТЕРУ' using errcode='P0002'; end if;
  if v_member=v_owner then raise exception 'Нельзя добавить самого себя' using errcode='22023'; end if;
  select count(*) into v_count from public.business_team_members tm where tm.owner_user_id=v_owner;
  if v_count>=5 and not exists(select 1 from public.business_team_members tm where tm.owner_user_id=v_owner and tm.member_user_id=v_member) then
    raise exception 'В тарифе Business можно добавить до 5 участников' using errcode='23514';
  end if;
  insert into public.business_team_members(owner_user_id,member_user_id,member_email)
  values(v_owner,v_member,v_email)
  on conflict(owner_user_id,member_user_id) do nothing
  returning id into v_membership;
  if v_membership is null then return jsonb_build_object('ok',true,'already_member',true); end if;
  select p.display_name into v_owner_name from public.profiles p where p.id=v_owner;
  insert into public.notifications(user_id,actor_id,type,title,body)
  values(v_member,v_owner,'business_team_invite','Доступ к команде Business',
    coalesce(nullif(v_owner_name,''),'Владелец аккаунта')||' предоставил вам командный доступ к объявлениям и статистике.');
  return jsonb_build_object('ok',true,'membership_id',v_membership,'member_email',v_email);
end;
$function$;

CREATE OR REPLACE FUNCTION private.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_wallet public.promotion_credit_wallets%rowtype;
  v_end timestamptz;
  v_promotion_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_plan_code not in ('boost_24h','highlight_7d','vip_7d') then raise exception 'Unsupported promotion credit' using errcode = '22023'; end if;
  if not exists(select 1 from public.listings l where l.id=p_listing_id and l.user_id=v_user_id and l.status='active') then
    raise exception 'Active listing owned by user is required' using errcode = '42501';
  end if;
  select w.* into v_wallet
  from public.promotion_credit_wallets w
  join public.user_subscriptions us on us.id=w.subscription_id
  where w.user_id=v_user_id and w.starts_at<=now() and w.ends_at>now()
    and us.status='active' and us.starts_at<=now() and us.ends_at>now()
    and us.plan_code='pro_plus'
    and ((p_plan_code='boost_24h' and w.boost_credits>0)
      or (p_plan_code='highlight_7d' and w.highlight_credits>0)
      or (p_plan_code='vip_7d' and w.vip_credits>0))
  order by w.ends_at desc limit 1 for update of w;
  if not found then raise exception 'No active credit for this promotion' using errcode = 'P0002'; end if;
  update public.promotion_credit_wallets
  set boost_credits=boost_credits-case when p_plan_code='boost_24h' then 1 else 0 end,
      highlight_credits=highlight_credits-case when p_plan_code='highlight_7d' then 1 else 0 end,
      vip_credits=vip_credits-case when p_plan_code='vip_7d' then 1 else 0 end
  where id=v_wallet.id;
  v_end := now() + case when p_plan_code='boost_24h' then interval '24 hours' else interval '7 days' end;
  insert into public.listing_promotions
    (user_id,listing_id,plan_code,status,starts_at,ends_at,provider,provider_payment_id)
  values (v_user_id,p_listing_id,p_plan_code,'active',now(),v_end,'pro_plus_credit',
    'credit:'||v_wallet.id::text||':'||p_plan_code||':'||gen_random_uuid()::text)
  returning id into v_promotion_id;
  return jsonb_build_object('ok',true,'promotion_id',v_promotion_id,'plan_code',p_plan_code,'ends_at',v_end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.activate_paid_monetization_order(p_order_id uuid, p_provider text, p_provider_payment_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order public.monetization_orders%rowtype;
  v_plan public.monetization_plans%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_subscription_id uuid;
  v_promotion_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only trusted payment server may activate paid orders' using errcode = '42501';
  end if;
  if p_provider is null or length(trim(p_provider)) < 2 or p_provider_payment_id is null or length(trim(p_provider_payment_id)) < 1 then
    raise exception 'Provider and provider payment ID are required' using errcode = '22023';
  end if;

  select * into v_order from public.monetization_orders where id=p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = 'P0002'; end if;
  if v_order.status='paid' then
    if v_order.provider=p_provider and v_order.provider_payment_id=p_provider_payment_id then
      return jsonb_build_object('ok',true,'already_processed',true,'order_id',v_order.id);
    end if;
    raise exception 'Order already paid with a different payment reference' using errcode = '23505';
  end if;
  if v_order.status not in ('pending','requires_action') then
    raise exception 'Order is not payable in current status' using errcode = '55000';
  end if;

  select * into v_plan from public.monetization_plans where code=v_order.plan_code and is_active=true;
  if not found or v_plan.price_rub*100<>v_order.amount_kopeks then
    raise exception 'Plan price mismatch or inactive plan' using errcode = '22000';
  end if;

  v_start := now();
  if v_order.order_type='subscription' then
    -- A renewal of the same tier starts when the current period ends.
    -- Switching tiers replaces other active tiers so their limits do not stack.
    if exists (
      select 1 from public.user_subscriptions us
      where us.user_id=v_order.user_id and us.plan_code=v_order.plan_code
        and us.status='active' and us.ends_at>now()
    ) then
      select max(us.ends_at) into v_start
      from public.user_subscriptions us
      where us.user_id=v_order.user_id and us.plan_code=v_order.plan_code
        and us.status='active' and us.ends_at>now();
      update public.user_subscriptions
      set status='expired', updated_at=now()
      where user_id=v_order.user_id and status='active'
        and plan_code not in (v_order.plan_code,'free') and ends_at>now();
    else
      update public.user_subscriptions
      set status='expired', updated_at=now()
      where user_id=v_order.user_id and status='active' and ends_at>now();
    end if;
    update public.user_subscriptions
    set status='expired', updated_at=now()
    where user_id=v_order.user_id and plan_code='free' and status='active';
    v_end := v_start + make_interval(days=>coalesce(v_plan.period_days,30));
    insert into public.user_subscriptions
      (user_id,plan_code,status,starts_at,ends_at,provider,provider_payment_id)
    values
      (v_order.user_id,v_order.plan_code,'active',v_start,v_end,p_provider,p_provider_payment_id)
    returning id into v_subscription_id;
  elsif v_order.order_type='promotion' then
    if v_order.listing_id is null then raise exception 'Promotion order has no listing' using errcode = '22023'; end if;
    if not exists(select 1 from public.listings where id=v_order.listing_id and user_id=v_order.user_id) then
      raise exception 'Listing ownership check failed' using errcode = '42501';
    end if;
    v_end := now() + make_interval(days=>coalesce(v_plan.period_days,1));
    insert into public.listing_promotions
      (user_id,listing_id,plan_code,status,starts_at,ends_at,provider,provider_payment_id)
    values
      (v_order.user_id,v_order.listing_id,v_order.plan_code,'active',now(),v_end,p_provider,p_provider_payment_id)
    returning id into v_promotion_id;
  else
    raise exception 'Unsupported paid order type for automatic activation' using errcode = '22023';
  end if;

  update public.monetization_orders
  set status='paid',provider=p_provider,provider_payment_id=p_provider_payment_id,paid_at=now(),updated_at=now()
  where id=v_order.id;

  return jsonb_build_object('ok',true,'order_id',v_order.id,'subscription_id',v_subscription_id,'promotion_id',v_promotion_id,'activated_until',v_end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_exchange_deal(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
  v_other_user uuid;
begin
  if v_user is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;

  select * into v_proposal
  from public.exchange_proposals
  where id = p_proposal_id
  for update;

  if not found then
    raise exception 'Предложение обмена не найдено';
  end if;

  select * into v_listing
  from public.listings
  where id = v_proposal.listing_id;

  if not found then
    raise exception 'Объявление обмена не найдено';
  end if;

  if v_user <> v_proposal.sender_id and v_user <> v_listing.user_id then
    raise exception 'Отменить сделку может только один из её участников';
  end if;

  if v_proposal.status not in ('pending', 'accepted') then
    raise exception 'Эту сделку уже нельзя отменить';
  end if;

  if v_proposal.sender_completed_at is not null or v_proposal.owner_completed_at is not null then
    raise exception 'После подтверждения завершения отмена недоступна';
  end if;

  v_other_user := case when v_user = v_proposal.sender_id then v_listing.user_id else v_proposal.sender_id end;

  update public.exchange_proposals
  set status = 'cancelled'
  where id = v_proposal.id;

  insert into public.notifications(user_id, actor_id, type, title, body, listing_id, conversation_id, proposal_id)
  select v_other_user, v_user, 'exchange_proposal', 'Сделка отменена',
    'Второй участник отменил сделку. Подтверждение условий и завершения больше недоступно.',
    v_proposal.listing_id, c.id, v_proposal.id
  from (select 1) as seed
  left join public.conversations c on c.proposal_id = v_proposal.id;

  return jsonb_build_object('ok', true, 'status', 'cancelled');
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_exchange_completed(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
  v_sender_done boolean;
  v_owner_done boolean;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select * into v_proposal from public.exchange_proposals where id = p_proposal_id for update;
  if not found then raise exception 'Предложение не найдено'; end if;
  select * into v_listing from public.listings where id = v_proposal.listing_id;
  if not found then raise exception 'Объявление не найдено'; end if;
  if v_proposal.sender_id is null or v_proposal.sender_id = v_listing.user_id then raise exception 'Некорректные участники сделки'; end if;
  if v_user <> v_proposal.sender_id and v_user <> v_listing.user_id then raise exception 'Вы не участник этой сделки'; end if;
  if v_proposal.status <> 'accepted' then raise exception 'Сделка ещё не принята'; end if;
  if not v_proposal.sender_confirmed_terms or not v_proposal.owner_confirmed_terms then raise exception 'Сначала оба участника должны подтвердить окончательные условия'; end if;
  update public.exchange_proposals
  set sender_completed_at = case when v_user = v_proposal.sender_id then coalesce(sender_completed_at, now()) else sender_completed_at end,
      owner_completed_at = case when v_user = v_listing.user_id then coalesce(owner_completed_at, now()) else owner_completed_at end
  where id = p_proposal_id;
  select sender_completed_at is not null, owner_completed_at is not null into v_sender_done, v_owner_done from public.exchange_proposals where id = p_proposal_id;
  if v_sender_done and v_owner_done then
    perform 1 from public.listings where id = v_proposal.listing_id or id = v_proposal.offered_listing_id order by id for update;
    update public.exchange_proposals set status = 'completed' where id = p_proposal_id;
    update public.listings
    set status = 'archived'
    where ((id = v_proposal.listing_id and user_id = v_listing.user_id)
       or (id = v_proposal.offered_listing_id and user_id = v_proposal.sender_id))
      and status = 'active';
    return jsonb_build_object('ok', true, 'completed', true, 'status', 'completed', 'listings_archived', true);
  end if;
  return jsonb_build_object('ok', true, 'completed', false, 'sender_completed', v_sender_done, 'owner_completed', v_owner_done);
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_exchange_terms(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_user uuid := auth.uid(); v_proposal public.exchange_proposals%rowtype; v_listing public.listings%rowtype; v_sender_ok boolean; v_owner_ok boolean; begin if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if; select * into v_proposal from public.exchange_proposals where id=p_proposal_id for update; if not found then raise exception 'Предложение не найдено'; end if; select * into v_listing from public.listings where id=v_proposal.listing_id; if not found then raise exception 'Объявление не найдено'; end if; if v_proposal.sender_id is null or v_proposal.sender_id=v_listing.user_id then raise exception 'Некорректные участники сделки'; end if; if v_user<>v_proposal.sender_id and v_user<>v_listing.user_id then raise exception 'Вы не участник этой сделки'; end if; if v_proposal.status<>'accepted' then raise exception 'Сделка ещё не принята'; end if; update public.exchange_proposals set sender_confirmed_terms=case when v_user=v_proposal.sender_id then true else sender_confirmed_terms end, owner_confirmed_terms=case when v_user=v_listing.user_id then true else owner_confirmed_terms end where id=p_proposal_id; select sender_confirmed_terms,owner_confirmed_terms into v_sender_ok,v_owner_ok from public.exchange_proposals where id=p_proposal_id; return jsonb_build_object('ok',true,'sender_confirmed',v_sender_ok,'owner_confirmed',v_owner_ok,'terms_agreed',v_sender_ok and v_owner_ok); end; $function$;

CREATE OR REPLACE FUNCTION public.enforce_active_listing_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_limit integer;
  v_active_count integer;
begin
  if new.status <> 'active' then
    return new;
  end if;

  -- Serialize concurrent active-listing writes for the same owner.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text, 0));

  select max(mp.active_listing_limit)
    into v_limit
  from public.user_subscriptions us
  join public.monetization_plans mp on mp.code = us.plan_code
  where us.user_id = new.user_id
    and us.status = 'active'
    and us.starts_at <= now()
    and us.ends_at > now()
    and mp.is_active = true;

  if v_limit is null then
    select mp.active_listing_limit
      into v_limit
    from public.monetization_plans mp
    where mp.code = 'free' and mp.is_active = true
    limit 1;
  end if;

  v_limit := coalesce(v_limit, 3);

  select count(*)
    into v_active_count
  from public.listings l
  where l.user_id = new.user_id
    and l.status = 'active'
    and (tg_op = 'INSERT' or l.id is distinct from new.id);

  if v_active_count >= v_limit then
    raise exception 'ACTIVE_LISTING_LIMIT_REACHED:%', v_limit
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.expire_unconfirmed_exchange_proposals()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_proposal record;
  v_count integer := 0;
  v_listing public.listings%rowtype;
  v_conversation uuid;
begin
  for v_proposal in
    select p.id,p.listing_id,p.sender_id,p.accepted_at
    from public.exchange_proposals p
    where p.status='accepted' and p.accepted_at is not null
      and p.accepted_at <= now() - interval '1 hour'
      and not (p.sender_confirmed_terms and p.owner_confirmed_terms)
      and p.sender_completed_at is null and p.owner_completed_at is null
    order by p.accepted_at for update skip locked
  loop
    select * into v_listing from public.listings where id=v_proposal.listing_id;
    if not found then continue; end if;
    select c.id into v_conversation from public.conversations c where c.proposal_id=v_proposal.id limit 1;
    update public.exchange_proposals set status='cancelled' where id=v_proposal.id and status='accepted';
    if not found then continue; end if;
    insert into public.notifications(user_id,actor_id,type,title,body,listing_id,conversation_id,proposal_id)
    values
      (v_proposal.sender_id,null,'exchange_proposal','Сделка отменена по таймеру','Час на подтверждение условий истёк. Предложение отменено; объявление снова доступно, если оно активно.',v_proposal.listing_id,v_conversation,v_proposal.id),
      (v_listing.user_id,null,'exchange_proposal','Сделка отменена по таймеру','Час на подтверждение условий истёк. Предложение отменено; объявление снова доступно, если оно активно.',v_proposal.listing_id,v_conversation,v_proposal.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_active_listing_subscriptions()
 RETURNS TABLE(user_id uuid, plan_code text, starts_at timestamp with time zone, ends_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select distinct on (s.user_id) s.user_id, s.plan_code, s.starts_at, s.ends_at
  from public.user_subscriptions s
  where s.status = 'active'
    and s.starts_at <= now()
    and s.ends_at > now()
    and exists (select 1 from public.listings l where l.user_id = s.user_id and l.status = 'active')
  order by s.user_id,
    case s.plan_code when 'business' then 3 when 'pro_plus' then 2 when 'pro' then 1 else 0 end desc,
    s.ends_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_listing_view_stats()
 RETURNS TABLE(listing_id uuid, total_views bigint, views_7d bigint, views_30d bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    lv.listing_id,
    count(*)::bigint as total_views,
    count(*) filter (where lv.viewed_at >= now() - interval '7 days')::bigint as views_7d,
    count(*) filter (where lv.viewed_at >= now() - interval '30 days')::bigint as views_30d
  from public.listing_views lv
  group by lv.listing_id;
$function$;

CREATE OR REPLACE FUNCTION public.grant_pro_plus_promotion_credits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.plan_code = 'pro_plus' and new.status = 'active' then
    insert into public.promotion_credit_wallets
      (user_id, subscription_id, boost_credits, highlight_credits, vip_credits, starts_at, ends_at)
    values
      (new.user_id, new.id, 1, 1, 1, new.starts_at, new.ends_at)
    on conflict (subscription_id) do nothing;
  elsif new.plan_code = 'pro_plus' and new.status <> 'active' then
    update public.promotion_credit_wallets
       set ends_at = least(ends_at, now())
     where subscription_id = new.id;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_exchange_proposal_status_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status is not distinct from old.status then return new; end if;
  if old.status = 'pending' and new.status in ('accepted', 'declined', 'cancelled') then return new; end if;
  if old.status = 'accepted' and new.status in ('completed', 'cancelled') then return new; end if;
  raise exception 'Недопустимый переход статуса предложения: % -> %', old.status, new.status using errcode = 'check_violation';
end;
$function$;

CREATE OR REPLACE FUNCTION public.invite_business_team_member(p_email text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.invite_business_team_member(p_email);
$function$;

CREATE OR REPLACE FUNCTION public.mark_conversation_messages_read(p_conversation_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_count integer;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.participant_one = v_user_id or c.participant_two = v_user_id)
  ) then raise exception 'Conversation not found or access denied'; end if;
  update public.messages m
     set read_at = now()
   where m.conversation_id = p_conversation_id
     and m.sender_id <> v_user_id
     and m.read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_exchange_contacts_reminder()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_listing_owner uuid;
  v_conversation_id uuid;
begin
  if new.status <> 'accepted'
     or new.sender_confirmed_terms is not true
     or new.owner_confirmed_terms is not true
     or (old.sender_confirmed_terms is true and old.owner_confirmed_terms is true and old.terms_version = new.terms_version) then
    return new;
  end if;

  select l.user_id into v_listing_owner
  from public.listings l
  where l.id = new.listing_id;

  select c.id into v_conversation_id
  from public.conversations c
  where c.proposal_id = new.id
  order by c.created_at desc
  limit 1;

  if v_listing_owner is null or new.sender_id is null or v_conversation_id is null then
    return new;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, listing_id, conversation_id, proposal_id)
  values
    (new.sender_id, null, 'exchange_contacts', 'Обменяйтесь контактами',
     'Условия согласованы. До подтверждения завершения обменяйтесь контактами и договоритесь о месте и времени встречи. После завершения переписка закроется.',
     new.listing_id, v_conversation_id, new.id),
    (v_listing_owner, null, 'exchange_contacts', 'Обменяйтесь контактами',
     'Условия согласованы. До подтверждения завершения обменяйтесь контактами и договоритесь о месте и времени встречи. После завершения переписка закроется.',
     new.listing_id, v_conversation_id, new.id);

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_exchange_proposal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare owner_id uuid; listing_title text;
begin
  select user_id, title into owner_id, listing_title from public.listings where id = new.listing_id;
  if owner_id is not null and owner_id <> new.sender_id then
    insert into public.notifications(user_id, actor_id, type, title, body, listing_id, proposal_id)
    values(owner_id, new.sender_id, 'exchange_proposal', 'Новое предложение обмена', coalesce(nullif(new.message,''), 'Пользователь предложил обмен') || case when listing_title is not null then ' · ' || listing_title else '' end, new.listing_id, new.id);
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notify_exchange_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.reviewer_id is null
     or new.reviewed_user_id is null
     or new.reviewer_id = new.reviewed_user_id then
    return new;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, proposal_id)
  values
    (new.reviewed_user_id,
     new.reviewer_id,
     'exchange_review',
     'Новый отзыв о тебе',
     'Отзыв о завершённом обмене будет опубликован после встречного отзыва или через 24 часа.',
     new.proposal_id);

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_exchange_terms_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_listing_owner uuid;
  v_other_user uuid;
  v_conversation_id uuid;
begin
  if new.status <> 'accepted'
     or new.terms_version is not distinct from old.terms_version then
    return new;
  end if;

  select l.user_id into v_listing_owner
  from public.listings l
  where l.id = new.listing_id;

  if v_listing_owner is null or new.sender_id is null then
    return new;
  end if;

  if new.sender_confirmed_terms is true and new.owner_confirmed_terms is not true then
    v_other_user := v_listing_owner;
  elsif new.owner_confirmed_terms is true and new.sender_confirmed_terms is not true then
    v_other_user := new.sender_id;
  else
    return new;
  end if;

  select c.id into v_conversation_id
  from public.conversations c
  where c.proposal_id = new.id
  order by c.created_at desc
  limit 1;

  if v_other_user is null or v_conversation_id is null then
    return new;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, listing_id, conversation_id, proposal_id)
  values
    (v_other_user, auth.uid(), 'exchange_terms', 'Изменены условия сделки',
     'Собеседник изменил условия обмена. Проверь новые условия и подтверди их.',
     new.listing_id, v_conversation_id, new.id);

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_new_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare recipient_id uuid; conv record;
begin
  select participant_one, participant_two into conv from public.conversations where id = new.conversation_id;
  if conv.participant_one is null then return new; end if;
  if new.sender_id = conv.participant_one then recipient_id := conv.participant_two; else recipient_id := conv.participant_one; end if;
  if recipient_id is not null and recipient_id <> new.sender_id then
    insert into public.notifications(user_id, actor_id, type, title, body, conversation_id, proposal_id)
    values(recipient_id, new.sender_id, 'message', 'Новое сообщение', left(coalesce(new.body,''), 180), new.conversation_id, (select proposal_id from public.conversations where id = new.conversation_id));
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notify_saved_search_matches()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status <> 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' then return new; end if;
  insert into public.notifications(user_id, actor_id, type, title, body, listing_id)
  select distinct ss.user_id, new.user_id, 'saved_search_match', 'Новое совпадение',
    'Объявление «' || left(new.title, 120) || '»' ||
    case when coalesce(new.city, '') <> '' then ' · ' || new.city else '' end,
    new.id
  from public.saved_searches ss
  where ss.is_active = true
    and ss.user_id <> new.user_id
    and (ss.category is null or ss.category = '' or ss.category = 'Все' or ss.category = new.category)
    and (coalesce(trim(ss.city), '') = '' or new.city ilike '%' || trim(ss.city) || '%')
    and (ss.min_price is null or (new.estimated_value is not null and new.estimated_value >= ss.min_price))
    and (ss.max_price is null or (new.estimated_value is not null and new.estimated_value <= ss.max_price))
    and (coalesce(trim(ss.query_text),'')='' or
      new.title ilike '%'||trim(ss.query_text)||'%' or
      new.want ilike '%'||trim(ss.query_text)||'%' or
      new.description ilike '%'||trim(ss.query_text)||'%')
    and exists (
      select 1 from public.user_subscriptions us
      where us.user_id=ss.user_id and us.plan_code in ('pro','pro_plus','business')
        and us.status='active' and us.starts_at<=now() and us.ends_at>now()
    );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_delete_listing_with_exchange_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.exchange_proposals p
    WHERE p.listing_id = OLD.id OR p.offered_listing_id = OLD.id
  ) OR EXISTS (
    SELECT 1
    FROM public.listing_promotions lp
    WHERE lp.listing_id = OLD.id
  ) OR EXISTS (
    SELECT 1
    FROM public.reports r
    WHERE r.listing_id = OLD.id
  ) THEN
    RAISE EXCEPTION 'LISTING_HAS_RETAINED_HISTORY: archive the listing instead of deleting it'
      USING ERRCODE = '23514';
  END IF;

  RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_proposals_for_completed_exchange_listings()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status not in ('pending', 'accepted') then
    return new;
  end if;

  if exists (
    select 1
    from public.exchange_proposals ep
    where ep.status = 'completed'
      and (
        ep.listing_id = new.listing_id
        or ep.offered_listing_id = new.listing_id
        or (
          new.offered_listing_id is not null
          and (ep.listing_id = new.offered_listing_id or ep.offered_listing_id = new.offered_listing_id)
        )
      )
  ) then
    raise exception 'Объявление уже участвовало в завершённом обмене. Создайте новое объявление для следующего обмена.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_reactivation_of_completed_exchange_listings()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.status = 'active'
     and old.status is distinct from 'active'
     and exists (
       select 1
       from public.exchange_proposals ep
       where ep.status = 'completed'
         and (ep.listing_id = old.id or ep.offered_listing_id = old.id)
     ) then
    raise exception 'Объявление участвовало в завершённом обмене и не может быть опубликовано повторно. Создайте новое объявление.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.redeem_pro_plus_promotion_credit(p_listing_id,p_plan_code);
$function$;

CREATE OR REPLACE FUNCTION public.reject_client_monetization_order_mutations()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Заказы может изменять только сервер обработки платежей'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_to_exchange_proposal(p_proposal_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
  v_offered public.listings%rowtype;
  v_conversation uuid;
  v_accepted_at timestamptz;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if p_decision is null or p_decision not in ('accepted','declined') then raise exception 'Недопустимое действие'; end if;
  select * into v_proposal from public.exchange_proposals where id=p_proposal_id for update;
  if not found then raise exception 'Предложение не найдено'; end if;
  perform 1 from public.listings where id=v_proposal.listing_id or id=v_proposal.offered_listing_id order by id for update;
  select * into v_listing from public.listings where id=v_proposal.listing_id;
  if not found then raise exception 'Объявление не найдено'; end if;
  if v_proposal.sender_id is null or v_proposal.sender_id=v_listing.user_id then raise exception 'Некорректные участники предложения'; end if;
  if v_listing.user_id<>v_user then raise exception 'Только владелец объявления может ответить на предложение'; end if;
  if v_proposal.status<>'pending' then raise exception 'На это предложение уже ответили'; end if;
  if p_decision='accepted' then
    if v_listing.status<>'active' then raise exception 'Объявление уже неактивно. Обновите предложение перед принятием'; end if;
    if v_proposal.offered_listing_id is not null then
      select * into v_offered from public.listings where id=v_proposal.offered_listing_id;
      if not found or v_offered.user_id<>v_proposal.sender_id or v_offered.status<>'active' then raise exception 'Предложенное в обмен объявление больше недоступно'; end if;
    end if;
  end if;
  v_accepted_at := case when p_decision='accepted' then now() else null end;
  update public.exchange_proposals set status=p_decision, accepted_at=v_accepted_at where id=v_proposal.id;
  if p_decision='accepted' then
    insert into public.conversations(proposal_id,participant_one,participant_two)
    values(v_proposal.id,v_user,v_proposal.sender_id)
    on conflict(proposal_id) do update set proposal_id=excluded.proposal_id
    returning id into v_conversation;
  end if;
  insert into public.notifications(user_id,actor_id,type,title,body,listing_id,conversation_id,proposal_id)
  values(v_proposal.sender_id,v_user,'exchange_proposal',
    case when p_decision='accepted' then 'Предложение принято' else 'Предложение отклонено' end,
    case when p_decision='accepted' then 'Владелец объявления принял предложение. Подтвердите условия обмена в течение часа.' else 'Владелец объявления отклонил предложение обмена.' end,
    v_proposal.listing_id,v_conversation,v_proposal.id);
  return jsonb_build_object('ok',true,'status',p_decision,'conversation_id',v_conversation,'accepted_at',v_accepted_at);
end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_message_delivered_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.delivered_at := pg_catalog.now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_exchange_terms(p_proposal_id uuid, p_deal_type text, p_surcharge_amount numeric, p_surcharge_payer text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_user uuid := auth.uid(); v_proposal public.exchange_proposals%rowtype; v_listing public.listings%rowtype; begin if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if; if p_deal_type is null or p_deal_type not in ('barter','surcharge') then raise exception 'Недопустимый тип сделки'; end if; if p_deal_type='barter' and (coalesce(p_surcharge_amount,0)<>0 or p_surcharge_payer is distinct from 'none') then raise exception 'Для чистого бартера доплата должна быть нулевой'; end if; if p_deal_type='surcharge' and (p_surcharge_amount is null or p_surcharge_amount<=0 or p_surcharge_amount>100000000 or p_surcharge_payer is null or p_surcharge_payer not in ('sender','owner')) then raise exception 'Проверь сумму и сторону доплаты'; end if; select * into v_proposal from public.exchange_proposals where id=p_proposal_id for update; if not found then raise exception 'Предложение не найдено'; end if; select * into v_listing from public.listings where id=v_proposal.listing_id; if not found then raise exception 'Объявление не найдено'; end if; if v_proposal.sender_id is null or v_proposal.sender_id=v_listing.user_id then raise exception 'Некорректные участники сделки'; end if; if v_user<>v_proposal.sender_id and v_user<>v_listing.user_id then raise exception 'Вы не участник этой сделки'; end if; if v_proposal.status<>'accepted' then raise exception 'Сначала примите предложение и откройте чат'; end if; update public.exchange_proposals set deal_type=p_deal_type,surcharge_amount=case when p_deal_type='barter' then 0 else p_surcharge_amount end,surcharge_payer=case when p_deal_type='barter' then 'none' else p_surcharge_payer end,terms_version=terms_version+1,sender_confirmed_terms=(v_user=v_proposal.sender_id),owner_confirmed_terms=(v_user=v_listing.user_id),sender_completed_at=null,owner_completed_at=null where id=p_proposal_id; return jsonb_build_object('ok',true,'terms_version',v_proposal.terms_version+1,'message','Условия обновлены. Второй участник должен подтвердить новую версию.'); end; $function$;

-- Restrict function execution to the same roles as Production.
revoke all on function private.exchange_review_is_published(p_proposal_id uuid, p_reviewer_id uuid, p_reviewed_user_id uuid, p_created_at timestamp with time zone) from public, anon, authenticated, service_role;
revoke all on function private.invite_business_team_member(p_email text) from public, anon, authenticated, service_role;
revoke all on function private.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text) from public, anon, authenticated, service_role;
revoke all on function public.activate_paid_monetization_order(p_order_id uuid, p_provider text, p_provider_payment_id text) from public, anon, authenticated, service_role;
revoke all on function public.cancel_exchange_deal(p_proposal_id uuid) from public, anon, authenticated, service_role;
revoke all on function public.confirm_exchange_completed(p_proposal_id uuid) from public, anon, authenticated, service_role;
revoke all on function public.confirm_exchange_terms(p_proposal_id uuid) from public, anon, authenticated, service_role;
revoke all on function public.enforce_active_listing_limit() from public, anon, authenticated, service_role;
revoke all on function public.expire_unconfirmed_exchange_proposals() from public, anon, authenticated, service_role;
revoke all on function public.get_active_listing_subscriptions() from public, anon, authenticated, service_role;
revoke all on function public.get_my_listing_view_stats() from public, anon, authenticated, service_role;
revoke all on function public.grant_pro_plus_promotion_credits() from public, anon, authenticated, service_role;
revoke all on function public.guard_exchange_proposal_status_transition() from public, anon, authenticated, service_role;
revoke all on function public.invite_business_team_member(p_email text) from public, anon, authenticated, service_role;
revoke all on function public.mark_conversation_messages_read(p_conversation_id uuid) from public, anon, authenticated, service_role;
revoke all on function public.notify_exchange_contacts_reminder() from public, anon, authenticated, service_role;
revoke all on function public.notify_exchange_proposal() from public, anon, authenticated, service_role;
revoke all on function public.notify_exchange_review() from public, anon, authenticated, service_role;
revoke all on function public.notify_exchange_terms_changed() from public, anon, authenticated, service_role;
revoke all on function public.notify_new_message() from public, anon, authenticated, service_role;
revoke all on function public.notify_saved_search_matches() from public, anon, authenticated, service_role;
revoke all on function public.prevent_delete_listing_with_exchange_history() from public, anon, authenticated, service_role;
revoke all on function public.prevent_proposals_for_completed_exchange_listings() from public, anon, authenticated, service_role;
revoke all on function public.prevent_reactivation_of_completed_exchange_listings() from public, anon, authenticated, service_role;
revoke all on function public.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text) from public, anon, authenticated, service_role;
revoke all on function public.reject_client_monetization_order_mutations() from public, anon, authenticated, service_role;
revoke all on function public.respond_to_exchange_proposal(p_proposal_id uuid, p_decision text) from public, anon, authenticated, service_role;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
revoke all on function public.set_message_delivered_at() from public, anon, authenticated, service_role;
revoke all on function public.update_exchange_terms(p_proposal_id uuid, p_deal_type text, p_surcharge_amount numeric, p_surcharge_payer text) from public, anon, authenticated, service_role;
grant EXECUTE on function private.exchange_review_is_published(p_proposal_id uuid, p_reviewer_id uuid, p_reviewed_user_id uuid, p_created_at timestamp with time zone) to anon;
grant EXECUTE on function private.exchange_review_is_published(p_proposal_id uuid, p_reviewer_id uuid, p_reviewed_user_id uuid, p_created_at timestamp with time zone) to authenticated;
grant EXECUTE on function private.invite_business_team_member(p_email text) to authenticated;
grant EXECUTE on function private.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text) to authenticated;
grant EXECUTE on function public.activate_paid_monetization_order(p_order_id uuid, p_provider text, p_provider_payment_id text) to service_role;
grant EXECUTE on function public.cancel_exchange_deal(p_proposal_id uuid) to authenticated;
grant EXECUTE on function public.cancel_exchange_deal(p_proposal_id uuid) to service_role;
grant EXECUTE on function public.confirm_exchange_completed(p_proposal_id uuid) to authenticated;
grant EXECUTE on function public.confirm_exchange_completed(p_proposal_id uuid) to service_role;
grant EXECUTE on function public.confirm_exchange_terms(p_proposal_id uuid) to authenticated;
grant EXECUTE on function public.confirm_exchange_terms(p_proposal_id uuid) to service_role;
grant EXECUTE on function public.enforce_active_listing_limit() to service_role;
grant EXECUTE on function public.expire_unconfirmed_exchange_proposals() to service_role;
grant EXECUTE on function public.get_active_listing_subscriptions() to service_role;
grant EXECUTE on function public.get_my_listing_view_stats() to authenticated;
grant EXECUTE on function public.get_my_listing_view_stats() to service_role;
grant EXECUTE on function public.grant_pro_plus_promotion_credits() to service_role;
grant EXECUTE on function public.guard_exchange_proposal_status_transition() to service_role;
grant EXECUTE on function public.invite_business_team_member(p_email text) to authenticated;
grant EXECUTE on function public.invite_business_team_member(p_email text) to service_role;
grant EXECUTE on function public.mark_conversation_messages_read(p_conversation_id uuid) to authenticated;
grant EXECUTE on function public.mark_conversation_messages_read(p_conversation_id uuid) to service_role;
grant EXECUTE on function public.notify_exchange_contacts_reminder() to service_role;
grant EXECUTE on function public.notify_exchange_proposal() to service_role;
grant EXECUTE on function public.notify_exchange_review() to service_role;
grant EXECUTE on function public.notify_exchange_terms_changed() to service_role;
grant EXECUTE on function public.notify_new_message() to service_role;
grant EXECUTE on function public.notify_saved_search_matches() to service_role;
grant EXECUTE on function public.prevent_delete_listing_with_exchange_history() to service_role;
grant EXECUTE on function public.prevent_proposals_for_completed_exchange_listings() to service_role;
grant EXECUTE on function public.prevent_reactivation_of_completed_exchange_listings() to service_role;
grant EXECUTE on function public.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text) to authenticated;
grant EXECUTE on function public.redeem_pro_plus_promotion_credit(p_listing_id uuid, p_plan_code text) to service_role;
grant EXECUTE on function public.reject_client_monetization_order_mutations() to service_role;
grant EXECUTE on function public.respond_to_exchange_proposal(p_proposal_id uuid, p_decision text) to authenticated;
grant EXECUTE on function public.respond_to_exchange_proposal(p_proposal_id uuid, p_decision text) to service_role;
grant EXECUTE on function public.rls_auto_enable() to service_role;
grant EXECUTE on function public.set_message_delivered_at() to service_role;
grant EXECUTE on function public.update_exchange_terms(p_proposal_id uuid, p_deal_type text, p_surcharge_amount numeric, p_surcharge_payer text) to authenticated;
grant EXECUTE on function public.update_exchange_terms(p_proposal_id uuid, p_deal_type text, p_surcharge_amount numeric, p_surcharge_payer text) to service_role;

-- Enable RLS on all application tables.
alter table public."business_team_members" enable row level security;
alter table public."conversations" enable row level security;
alter table public."exchange_proposals" enable row level security;
alter table public."exchange_reviews" enable row level security;
alter table public."favorites" enable row level security;
alter table public."listing_promotions" enable row level security;
alter table public."listing_views" enable row level security;
alter table public."listings" enable row level security;
alter table public."messages" enable row level security;
alter table public."monetization_orders" enable row level security;
alter table public."monetization_plans" enable row level security;
alter table public."notifications" enable row level security;
alter table public."payment_webhook_events" enable row level security;
alter table public."profiles" enable row level security;
alter table public."promotion_credit_wallets" enable row level security;
alter table public."push_subscriptions" enable row level security;
alter table public."reports" enable row level security;
alter table public."saved_searches" enable row level security;
alter table public."support_tickets" enable row level security;
alter table public."user_hidden_conversations" enable row level security;
alter table public."user_hidden_exchange_proposals" enable row level security;
alter table public."user_subscriptions" enable row level security;

-- Policies. Existing support-ticket policies already match Production exactly.
create policy "Business owners can remove team members" on public."business_team_members" as permissive for delete to authenticated using ((owner_user_id = ( SELECT auth.uid() AS uid)));
create policy "Business users and invited members can view team" on public."business_team_members" as permissive for select to authenticated using (((owner_user_id = ( SELECT auth.uid() AS uid)) OR (member_user_id = ( SELECT auth.uid() AS uid))));
create policy "Participants create conversations" on public."conversations" as permissive for insert to authenticated with check ((((( SELECT auth.uid() AS uid) = participant_one) OR (( SELECT auth.uid() AS uid) = participant_two)) AND (participant_one <> participant_two) AND (EXISTS ( SELECT 1
   FROM (exchange_proposals ep
     JOIN listings l ON ((l.id = ep.listing_id)))
  WHERE ((ep.id = conversations.proposal_id) AND (ep.status = 'accepted'::text) AND (((conversations.participant_one = l.user_id) AND (conversations.participant_two = ep.sender_id)) OR ((conversations.participant_two = l.user_id) AND (conversations.participant_one = ep.sender_id))))))));
create policy "Participants view conversations" on public."conversations" as permissive for select to public using (((( SELECT auth.uid() AS uid) = participant_one) OR (( SELECT auth.uid() AS uid) = participant_two)));
create policy "Proposal participants can view" on public."exchange_proposals" as permissive for select to public using (((( SELECT auth.uid() AS uid) = sender_id) OR (( SELECT auth.uid() AS uid) = ( SELECT l.user_id
   FROM listings l
  WHERE (l.id = exchange_proposals.listing_id)))));
create policy "Users create proposals as themselves" on public."exchange_proposals" as permissive for insert to authenticated with check (((sender_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND (terms_version = 1) AND (sender_confirmed_terms = true) AND (owner_confirmed_terms = false) AND (sender_completed_at IS NULL) AND (owner_completed_at IS NULL) AND (EXISTS ( SELECT 1
   FROM listings target
  WHERE ((target.id = exchange_proposals.listing_id) AND (target.status = 'active'::text) AND (target.user_id <> ( SELECT auth.uid() AS uid))))) AND ((offered_listing_id IS NULL) OR (EXISTS ( SELECT 1
   FROM listings offered
  WHERE ((offered.id = exchange_proposals.offered_listing_id) AND (offered.status = 'active'::text) AND (offered.user_id = ( SELECT auth.uid() AS uid))))))));
create policy "Exchange reviews are readable when published or by author" on public."exchange_reviews" as permissive for select to anon, authenticated using (((reviewer_id = ( SELECT auth.uid() AS uid)) OR private.exchange_review_is_published(proposal_id, reviewer_id, reviewed_user_id, created_at)));
create policy "Participants can review completed exchanges" on public."exchange_reviews" as permissive for insert to authenticated with check (((reviewer_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (exchange_proposals p
     JOIN conversations c ON ((c.proposal_id = p.id)))
  WHERE ((p.id = exchange_reviews.proposal_id) AND (p.sender_completed_at IS NOT NULL) AND (p.owner_completed_at IS NOT NULL) AND ((exchange_reviews.reviewer_id = c.participant_one) OR (exchange_reviews.reviewer_id = c.participant_two)) AND ((exchange_reviews.reviewed_user_id = c.participant_one) OR (exchange_reviews.reviewed_user_id = c.participant_two)) AND (exchange_reviews.reviewed_user_id <> exchange_reviews.reviewer_id))))));
create policy "Users add own favorites" on public."favorites" as permissive for insert to public with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users remove own favorites" on public."favorites" as permissive for delete to public using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users view own favorites" on public."favorites" as permissive for select to public using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Anyone can read active listing promotions" on public."listing_promotions" as permissive for select to anon using (((status = 'active'::text) AND (starts_at <= now()) AND (ends_at > now())));
create policy "Users can read active promotions and their own promotions" on public."listing_promotions" as permissive for select to authenticated using (((status = 'active'::text) OR (user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid))));
create policy "Paid owners and active Business team can read listing views" on public."listing_views" as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_views.listing_id) AND (((l.user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
           FROM user_subscriptions us
          WHERE ((us.user_id = l.user_id) AND (us.plan_code = ANY (ARRAY['pro_plus'::text, 'business'::text])) AND (us.status = 'active'::text) AND (us.starts_at <= now()) AND (us.ends_at > now()))))) OR ((EXISTS ( SELECT 1
           FROM business_team_members tm
          WHERE ((tm.owner_user_id = l.user_id) AND (tm.member_user_id = ( SELECT auth.uid() AS uid))))) AND (EXISTS ( SELECT 1
           FROM user_subscriptions us
          WHERE ((us.user_id = l.user_id) AND (us.plan_code = 'business'::text) AND (us.status = 'active'::text) AND (us.starts_at <= now()) AND (us.ends_at > now()))))))))));
create policy "Visitors can record listing views" on public."listing_views" as permissive for insert to anon, authenticated with check (((((( SELECT auth.uid() AS uid) IS NULL) AND (viewer_id IS NULL)) OR ((( SELECT auth.uid() AS uid) IS NOT NULL) AND (viewer_id = ( SELECT auth.uid() AS uid)))) AND (EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = listing_views.listing_id) AND (l.status = 'active'::text) AND (l.user_id IS DISTINCT FROM ( SELECT auth.uid() AS uid)))))));
create policy "Active listings are public" on public."listings" as permissive for select to public using (((status = 'active'::text) OR (( SELECT auth.uid() AS uid) = user_id)));
create policy "Owners delete own listings" on public."listings" as permissive for delete to public using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Owners update own listings" on public."listings" as permissive for update to public using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users create own listings" on public."listings" as permissive for insert to public with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Participants send messages only in active deals" on public."messages" as permissive for insert to authenticated with check (((sender_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (conversations c
     JOIN exchange_proposals ep ON ((ep.id = c.proposal_id)))
  WHERE ((c.id = messages.conversation_id) AND ((( SELECT auth.uid() AS uid) = c.participant_one) OR (( SELECT auth.uid() AS uid) = c.participant_two)) AND (ep.status = 'accepted'::text) AND (ep.sender_completed_at IS NULL) AND (ep.owner_completed_at IS NULL) AND (((ep.sender_confirmed_terms IS TRUE) AND (ep.owner_confirmed_terms IS TRUE)) OR (ep.accepted_at > (now() - '01:00:00'::interval))))))));
create policy "Participants view messages" on public."messages" as permissive for select to public using ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((( SELECT auth.uid() AS uid) = c.participant_one) OR (( SELECT auth.uid() AS uid) = c.participant_two))))));
create policy "Users delete own messages" on public."messages" as permissive for delete to authenticated using (((sender_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND ((c.participant_one = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) OR (c.participant_two = ( SELECT ( SELECT auth.uid() AS uid) AS uid))))))));
create policy "Users can read own monetization orders" on public."monetization_orders" as permissive for select to authenticated using ((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)));
create policy "Active monetization plans are readable by everyone" on public."monetization_plans" as permissive for select to anon, authenticated using ((is_active = true));
create policy "Users can mark own notifications read" on public."notifications" as permissive for update to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users can read own notifications" on public."notifications" as permissive for select to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users delete own notifications" on public."notifications" as permissive for delete to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Profiles are viewable" on public."profiles" as permissive for select to public using (true);
create policy "Users insert own profile" on public."profiles" as permissive for insert to public with check ((( SELECT auth.uid() AS uid) = id));
create policy "Users update own profile" on public."profiles" as permissive for update to public using ((( SELECT auth.uid() AS uid) = id)) with check ((( SELECT auth.uid() AS uid) = id));
create policy "Users can view their own promotion credits" on public."promotion_credit_wallets" as permissive for select to authenticated using ((user_id = ( SELECT auth.uid() AS uid)));
create policy "Users delete own push subscriptions" on public."push_subscriptions" as permissive for delete to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users insert own push subscriptions" on public."push_subscriptions" as permissive for insert to authenticated with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users read own push subscriptions" on public."push_subscriptions" as permissive for select to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users update own push subscriptions" on public."push_subscriptions" as permissive for update to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "Users create own reports" on public."reports" as permissive for insert to public with check ((( SELECT auth.uid() AS uid) = reporter_id));
create policy "Users view own reports" on public."reports" as permissive for select to public using ((( SELECT auth.uid() AS uid) = reporter_id));
create policy "Users manage their own saved searches" on public."saved_searches" as permissive for all to authenticated using ((user_id = ( SELECT auth.uid() AS uid))) with check ((user_id = ( SELECT auth.uid() AS uid)));
create policy "Users hide own conversations" on public."user_hidden_conversations" as permissive for insert to authenticated with check (((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = user_hidden_conversations.conversation_id) AND ((c.participant_one = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) OR (c.participant_two = ( SELECT ( SELECT auth.uid() AS uid) AS uid))))))));
create policy "Users unhide own conversations" on public."user_hidden_conversations" as permissive for delete to authenticated using ((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)));
create policy "Users view own hidden conversations" on public."user_hidden_conversations" as permissive for select to authenticated using ((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)));
create policy "Users hide visible exchange proposals" on public."user_hidden_exchange_proposals" as permissive for insert to authenticated with check (((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) AND (EXISTS ( SELECT 1
   FROM (exchange_proposals p
     LEFT JOIN listings l ON ((l.id = p.listing_id)))
  WHERE ((p.id = user_hidden_exchange_proposals.proposal_id) AND ((p.sender_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)) OR (l.user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid))))))));
create policy "Users unhide own exchange proposals" on public."user_hidden_exchange_proposals" as permissive for delete to authenticated using ((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)));
create policy "Users view own hidden exchange proposals" on public."user_hidden_exchange_proposals" as permissive for select to authenticated using ((user_id = ( SELECT ( SELECT auth.uid() AS uid) AS uid)));
create policy "Users can read own subscriptions" on public."user_subscriptions" as permissive for select to authenticated using ((user_id = ( SELECT auth.uid() AS uid)));
create policy "Authenticated users upload own listing images" on storage."objects" as permissive for insert to authenticated with check (((bucket_id = 'listing-images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
create policy "Public can view listing images" on storage."objects" as permissive for select to public using ((bucket_id = 'listing-images'::text));
create policy "Users delete own listing images" on storage."objects" as permissive for delete to authenticated using (((bucket_id = 'listing-images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
create policy "Users update own listing images" on storage."objects" as permissive for update to authenticated using (((bucket_id = 'listing-images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))) with check (((bucket_id = 'listing-images'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));

-- In-app triggers; external push dispatch is intentionally omitted.
CREATE TRIGGER exchange_contacts_reminder AFTER UPDATE OF sender_confirmed_terms, owner_confirmed_terms, terms_version ON public.exchange_proposals FOR EACH ROW EXECUTE FUNCTION notify_exchange_contacts_reminder();
CREATE TRIGGER exchange_proposal_notification AFTER INSERT ON public.exchange_proposals FOR EACH ROW EXECUTE FUNCTION notify_exchange_proposal();
CREATE TRIGGER exchange_terms_changed_notification AFTER UPDATE OF terms_version ON public.exchange_proposals FOR EACH ROW EXECUTE FUNCTION notify_exchange_terms_changed();
CREATE TRIGGER guard_exchange_proposal_status_transition BEFORE UPDATE OF status ON public.exchange_proposals FOR EACH ROW EXECUTE FUNCTION guard_exchange_proposal_status_transition();
CREATE TRIGGER prevent_proposals_for_completed_exchange_listings BEFORE INSERT OR UPDATE OF status, listing_id, offered_listing_id ON public.exchange_proposals FOR EACH ROW EXECUTE FUNCTION prevent_proposals_for_completed_exchange_listings();
CREATE TRIGGER exchange_review_notification AFTER INSERT ON public.exchange_reviews FOR EACH ROW EXECUTE FUNCTION notify_exchange_review();
CREATE TRIGGER enforce_active_listing_limit BEFORE INSERT OR UPDATE OF status, user_id ON public.listings FOR EACH ROW EXECUTE FUNCTION enforce_active_listing_limit();
CREATE TRIGGER listings_notify_saved_search_matches AFTER INSERT OR UPDATE OF status ON public.listings FOR EACH ROW EXECUTE FUNCTION notify_saved_search_matches();
CREATE TRIGGER prevent_delete_listing_with_exchange_history BEFORE DELETE ON public.listings FOR EACH ROW EXECUTE FUNCTION prevent_delete_listing_with_exchange_history();
CREATE TRIGGER prevent_reactivation_of_completed_exchange_listings BEFORE UPDATE OF status ON public.listings FOR EACH ROW EXECUTE FUNCTION prevent_reactivation_of_completed_exchange_listings();
CREATE TRIGGER message_notification AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION notify_new_message();
CREATE TRIGGER set_message_delivered_at BEFORE INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION set_message_delivered_at();
CREATE TRIGGER protect_monetization_orders_from_client_updates BEFORE UPDATE ON public.monetization_orders FOR EACH ROW EXECUTE FUNCTION reject_client_monetization_order_mutations();
CREATE TRIGGER user_subscriptions_grant_pro_plus_credits AFTER INSERT OR UPDATE OF status, plan_code, starts_at, ends_at ON public.user_subscriptions FOR EACH ROW EXECUTE FUNCTION grant_pro_plus_promotion_credits();

-- Match Production table grants.
revoke all on table public."business_team_members" from anon, authenticated, service_role;
revoke all on table public."conversations" from anon, authenticated, service_role;
revoke all on table public."exchange_proposals" from anon, authenticated, service_role;
revoke all on table public."exchange_reviews" from anon, authenticated, service_role;
revoke all on table public."favorites" from anon, authenticated, service_role;
revoke all on table public."listing_promotions" from anon, authenticated, service_role;
revoke all on table public."listing_views" from anon, authenticated, service_role;
revoke all on table public."listings" from anon, authenticated, service_role;
revoke all on table public."messages" from anon, authenticated, service_role;
revoke all on table public."monetization_orders" from anon, authenticated, service_role;
revoke all on table public."monetization_plans" from anon, authenticated, service_role;
revoke all on table public."notifications" from anon, authenticated, service_role;
revoke all on table public."payment_webhook_events" from anon, authenticated, service_role;
revoke all on table public."profiles" from anon, authenticated, service_role;
revoke all on table public."promotion_credit_wallets" from anon, authenticated, service_role;
revoke all on table public."push_subscriptions" from anon, authenticated, service_role;
revoke all on table public."reports" from anon, authenticated, service_role;
revoke all on table public."saved_searches" from anon, authenticated, service_role;
revoke all on table public."support_tickets" from anon, authenticated, service_role;
revoke all on table public."user_hidden_conversations" from anon, authenticated, service_role;
revoke all on table public."user_hidden_exchange_proposals" from anon, authenticated, service_role;
revoke all on table public."user_subscriptions" from anon, authenticated, service_role;
grant DELETE, SELECT on table public."business_team_members" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."business_team_members" to service_role;
grant INSERT, MAINTAIN, SELECT on table public."conversations" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."conversations" to service_role;
grant INSERT, MAINTAIN, SELECT on table public."exchange_proposals" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."exchange_proposals" to service_role;
grant SELECT on table public."exchange_reviews" to anon;
grant INSERT, SELECT on table public."exchange_reviews" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."exchange_reviews" to service_role;
grant DELETE, INSERT, MAINTAIN, SELECT, UPDATE on table public."favorites" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."favorites" to service_role;
grant MAINTAIN, SELECT on table public."listing_promotions" to anon;
grant MAINTAIN, SELECT on table public."listing_promotions" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."listing_promotions" to service_role;
grant INSERT on table public."listing_views" to anon;
grant INSERT, SELECT on table public."listing_views" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."listing_views" to service_role;
grant MAINTAIN, SELECT on table public."listings" to anon;
grant DELETE, INSERT, MAINTAIN, SELECT, UPDATE on table public."listings" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."listings" to service_role;
grant DELETE, INSERT, MAINTAIN, SELECT on table public."messages" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."messages" to service_role;
grant MAINTAIN, SELECT on table public."monetization_orders" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."monetization_orders" to service_role;
grant MAINTAIN, SELECT on table public."monetization_plans" to anon;
grant MAINTAIN, SELECT on table public."monetization_plans" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."monetization_plans" to service_role;
grant DELETE, MAINTAIN, SELECT on table public."notifications" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."notifications" to service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."payment_webhook_events" to service_role;
grant MAINTAIN, SELECT on table public."profiles" to anon;
grant INSERT, MAINTAIN, SELECT, UPDATE on table public."profiles" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."profiles" to service_role;
grant SELECT on table public."promotion_credit_wallets" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."promotion_credit_wallets" to service_role;
grant DELETE, INSERT, MAINTAIN, SELECT, UPDATE on table public."push_subscriptions" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."push_subscriptions" to service_role;
grant INSERT, MAINTAIN, SELECT on table public."reports" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."reports" to service_role;
grant DELETE, INSERT, SELECT, UPDATE on table public."saved_searches" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."saved_searches" to service_role;
grant INSERT, SELECT on table public."support_tickets" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."support_tickets" to service_role;
grant DELETE, INSERT, MAINTAIN, SELECT, UPDATE on table public."user_hidden_conversations" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_hidden_conversations" to service_role;
grant DELETE, INSERT, MAINTAIN, SELECT, UPDATE on table public."user_hidden_exchange_proposals" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_hidden_exchange_proposals" to service_role;
grant MAINTAIN, SELECT on table public."user_subscriptions" to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on table public."user_subscriptions" to service_role;

-- Storage bucket configuration only; no objects are copied.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types) values ('listing-images','listing-images',true,5242880,array['image/jpeg','image/png','image/webp','image/gif']::text[]) on conflict (id) do update set name=excluded.name,public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Realtime publication membership.
do $staging$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='exchange_proposals') then alter publication supabase_realtime add table public."exchange_proposals"; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then alter publication supabase_realtime add table public."messages"; end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then alter publication supabase_realtime add table public."notifications"; end if;
exception when undefined_object then raise notice 'supabase_realtime publication unavailable'; end $staging$;

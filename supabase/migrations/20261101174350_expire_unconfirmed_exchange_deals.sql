create or replace function public.expire_exchange_proposal_if_needed(p_proposal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_proposal public.exchange_proposals%rowtype;
  v_owner_id uuid;
  v_other_user uuid;
begin
  if v_user is null then
    raise exception 'Необходимо войти в аккаунт';
  end if;
  select * into v_proposal from public.exchange_proposals where id = p_proposal_id for update;
  if not found then raise exception 'Предложение обмена не найдено'; end if;
  select user_id into v_owner_id from public.listings where id = v_proposal.listing_id;
  if v_owner_id is null then raise exception 'Объявление обмена не найдено'; end if;
  if v_user <> v_proposal.sender_id and v_user <> v_owner_id then raise exception 'Вы не участник этой сделки'; end if;
  if v_proposal.status <> 'accepted'
     or v_proposal.accepted_at is null
     or v_proposal.accepted_at > now() - interval '1 hour'
     or (v_proposal.sender_confirmed_terms and v_proposal.owner_confirmed_terms)
     or v_proposal.sender_completed_at is not null
     or v_proposal.owner_completed_at is not null then
    return jsonb_build_object('ok', true, 'expired', false, 'status', v_proposal.status);
  end if;
  v_other_user := case when v_user = v_proposal.sender_id then v_owner_id else v_proposal.sender_id end;
  update public.exchange_proposals set status = 'cancelled' where id = v_proposal.id;
  insert into public.notifications(user_id, actor_id, type, title, body, listing_id, conversation_id, proposal_id)
  select v_other_user, v_user, 'exchange_proposal', 'Срок подтверждения истёк',
    'Условия обмена не были подтверждены обоими участниками в течение часа. Сделка отменена, объявления снова доступны.',
    v_proposal.listing_id, c.id, v_proposal.id
  from (select 1) as seed left join public.conversations c on c.proposal_id = v_proposal.id;
  return jsonb_build_object('ok', true, 'expired', true, 'status', 'cancelled');
end;
$function$;
revoke execute on function public.expire_exchange_proposal_if_needed(uuid) from public;
revoke execute on function public.expire_exchange_proposal_if_needed(uuid) from anon;
grant execute on function public.expire_exchange_proposal_if_needed(uuid) to authenticated;

create or replace function public.confirm_exchange_terms(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_expiration jsonb;
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
  v_sender_ok boolean;
  v_owner_ok boolean;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  v_expiration := public.expire_exchange_proposal_if_needed(p_proposal_id);
  if coalesce((v_expiration->>'expired')::boolean, false) then
    return jsonb_build_object('ok', false, 'expired', true, 'status', 'cancelled');
  end if;
  select * into v_proposal from public.exchange_proposals where id = p_proposal_id for update;
  if not found then raise exception 'Предложение не найдено'; end if;
  select * into v_listing from public.listings where id = v_proposal.listing_id;
  if not found then raise exception 'Объявление не найдено'; end if;
  if v_proposal.sender_id is null or v_proposal.sender_id = v_listing.user_id then raise exception 'Некорректные участники сделки'; end if;
  if v_user <> v_proposal.sender_id and v_user <> v_listing.user_id then raise exception 'Вы не участник этой сделки'; end if;
  if v_proposal.status <> 'accepted' then raise exception 'Сделка ещё не принята'; end if;
  update public.exchange_proposals
  set sender_confirmed_terms = case when v_user = v_proposal.sender_id then true else sender_confirmed_terms end,
      owner_confirmed_terms = case when v_user = v_listing.user_id then true else owner_confirmed_terms end
  where id = p_proposal_id;
  select sender_confirmed_terms, owner_confirmed_terms into v_sender_ok, v_owner_ok
  from public.exchange_proposals where id = p_proposal_id;
  return jsonb_build_object('ok', true, 'sender_confirmed', v_sender_ok, 'owner_confirmed', v_owner_ok, 'terms_agreed', v_sender_ok and v_owner_ok);
end;
$function$;

create or replace function public.update_exchange_terms(p_proposal_id uuid,p_deal_type text,p_surcharge_amount numeric,p_surcharge_payer text)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_expiration jsonb;
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  v_expiration := public.expire_exchange_proposal_if_needed(p_proposal_id);
  if coalesce((v_expiration->>'expired')::boolean, false) then
    return jsonb_build_object('ok', false, 'expired', true, 'status', 'cancelled');
  end if;
  if p_deal_type is null or p_deal_type not in ('barter','surcharge') then raise exception 'Недопустимый тип сделки'; end if;
  if p_deal_type = 'barter' and (coalesce(p_surcharge_amount,0) <> 0 or p_surcharge_payer is distinct from 'none') then
    raise exception 'Для чистого бартера доплата должна быть нулевой';
  end if;
  if p_deal_type = 'surcharge' and (p_surcharge_amount is null or p_surcharge_amount <= 0 or p_surcharge_amount > 100000000
    or p_surcharge_payer is null or p_surcharge_payer not in ('sender','owner')) then
    raise exception 'Проверь сумму и сторону доплаты';
  end if;
  select * into v_proposal from public.exchange_proposals where id = p_proposal_id for update;
  if not found then raise exception 'Предложение не найдено'; end if;
  select * into v_listing from public.listings where id = v_proposal.listing_id;
  if not found then raise exception 'Объявление не найдено'; end if;
  if v_proposal.sender_id is null or v_proposal.sender_id = v_listing.user_id then raise exception 'Некорректные участники сделки'; end if;
  if v_user <> v_proposal.sender_id and v_user <> v_listing.user_id then raise exception 'Вы не участник этой сделки'; end if;
  if v_proposal.status <> 'accepted' then raise exception 'Сначала примите предложение и откройте чат'; end if;
  update public.exchange_proposals
  set deal_type = p_deal_type,
      surcharge_amount = case when p_deal_type = 'barter' then 0 else p_surcharge_amount end,
      surcharge_payer = case when p_deal_type = 'barter' then 'none' else p_surcharge_payer end,
      terms_version = terms_version + 1,
      sender_confirmed_terms = (v_user = v_proposal.sender_id),
      owner_confirmed_terms = (v_user = v_listing.user_id),
      sender_completed_at = null,
      owner_completed_at = null
  where id = p_proposal_id;
  return jsonb_build_object('ok', true, 'terms_version', v_proposal.terms_version + 1, 'message', 'Условия обновлены. Второй участник должен подтвердить новую версию.');
end;
$function$;
revoke execute on function public.confirm_exchange_terms(uuid) from public;
revoke execute on function public.confirm_exchange_terms(uuid) from anon;
grant execute on function public.confirm_exchange_terms(uuid) to authenticated;
revoke execute on function public.update_exchange_terms(uuid,text,numeric,text) from public;
revoke execute on function public.update_exchange_terms(uuid,text,numeric,text) from anon;
grant execute on function public.update_exchange_terms(uuid,text,numeric,text) to authenticated;

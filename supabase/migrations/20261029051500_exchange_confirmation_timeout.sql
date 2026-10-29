alter table public.exchange_proposals
  add column if not exists accepted_at timestamptz;

create or replace function public.guard_exchange_proposal_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if old.status = 'pending' and new.status in ('accepted', 'declined', 'cancelled') then
    return new;
  end if;
  if old.status = 'accepted' and new.status in ('completed', 'cancelled') then
    return new;
  end if;
  raise exception 'Недопустимый переход статуса предложения: % -> %', old.status, new.status
    using errcode = 'check_violation';
end;
$function$;

create or replace function public.respond_to_exchange_proposal(p_proposal_id uuid, p_decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_proposal public.exchange_proposals%rowtype;
  v_listing public.listings%rowtype;
  v_offered public.listings%rowtype;
  v_conversation uuid;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  if p_decision is null or p_decision not in ('accepted','declined') then raise exception 'Недопустимое действие'; end if;
  select * into v_proposal from public.exchange_proposals where id=p_proposal_id for update;
  if not found then raise exception 'Предложение не найдено'; end if;
  perform 1 from public.listings
    where id=v_proposal.listing_id or id=v_proposal.offered_listing_id
    order by id for update;
  select * into v_listing from public.listings where id=v_proposal.listing_id;
  if not found then raise exception 'Объявление не найдено'; end if;
  if v_proposal.sender_id is null or v_proposal.sender_id=v_listing.user_id then raise exception 'Некорректные участники предложения'; end if;
  if v_listing.user_id<>v_user then raise exception 'Только владелец объявления может ответить на предложение'; end if;
  if v_proposal.status<>'pending' then raise exception 'На это предложение уже ответили'; end if;
  if p_decision='accepted' then
    if v_listing.status<>'active' then raise exception 'Объявление уже неактивно. Обновите предложение перед принятием'; end if;
    if v_proposal.offered_listing_id is not null then
      select * into v_offered from public.listings where id=v_proposal.offered_listing_id;
      if not found or v_offered.user_id<>v_proposal.sender_id or v_offered.status<>'active' then
        raise exception 'Предложенное в обмен объявление больше недоступно';
      end if;
    end if;
  end if;
  update public.exchange_proposals
  set status=p_decision, accepted_at=case when p_decision='accepted' then now() else null end
  where id=v_proposal.id;
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
  return jsonb_build_object('ok',true,'status',p_decision,'conversation_id',v_conversation,'accepted_at',case when p_decision='accepted' then now() else null end);
end;
$function$;

create or replace function public.expire_unconfirmed_exchange_proposals()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_proposal record;
  v_count integer := 0;
  v_listing public.listings%rowtype;
  v_conversation uuid;
begin
  for v_proposal in
    select p.id,p.listing_id,p.sender_id,p.accepted_at
    from public.exchange_proposals p
    where p.status='accepted'
      and p.accepted_at is not null
      and p.accepted_at <= now() - interval '1 hour'
      and not (p.sender_confirmed_terms and p.owner_confirmed_terms)
      and p.sender_completed_at is null
      and p.owner_completed_at is null
    order by p.accepted_at
    for update skip locked
  loop
    select * into v_listing from public.listings where id=v_proposal.listing_id;
    if not found then continue; end if;
    select c.id into v_conversation from public.conversations c where c.proposal_id=v_proposal.id limit 1;
    update public.exchange_proposals set status='cancelled' where id=v_proposal.id and status='accepted';
    if not found then continue; end if;

    insert into public.notifications(user_id,actor_id,type,title,body,listing_id,conversation_id,proposal_id)
    values
      (v_proposal.sender_id,null,'exchange_proposal','Сделка отменена по таймеру',
       'Час на подтверждение условий истёк. Предложение отменено, объявление снова доступно, если оно активно.',
       v_proposal.listing_id,v_conversation,v_proposal.id),
      (v_listing.user_id,null,'exchange_proposal','Сделка отменена по таймеру',
       'Час на подтверждение условий истёк. Предложение отменено, объявление снова доступно, если оно активно.',
       v_proposal.listing_id,v_conversation,v_proposal.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.expire_unconfirmed_exchange_proposals() from public, anon, authenticated;
grant execute on function public.expire_unconfirmed_exchange_proposals() to postgres, service_role;

create extension if not exists pg_cron with schema pg_catalog;

do $schedule$
begin
  if not exists (select 1 from cron.job where jobname='expire-unconfirmed-exchange-proposals') then
    perform cron.schedule(
      'expire-unconfirmed-exchange-proposals',
      '* * * * *',
      $job$select public.expire_unconfirmed_exchange_proposals();$job$
    );
  end if;
end;
$schedule$;
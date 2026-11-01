create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

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
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
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
  update public.exchange_proposals set status = 'cancelled' where id = v_proposal.id and status = 'accepted';
  if not found then return jsonb_build_object('ok', true, 'expired', false, 'status', 'cancelled'); end if;
  insert into public.notifications(user_id,actor_id,type,title,body,listing_id,conversation_id,proposal_id)
  select recipients.user_id,null,'exchange_proposal','Сделка отменена по таймеру',
    'Час на подтверждение условий истёк. Предложение отменено; объявление снова доступно, если оно активно.',
    v_proposal.listing_id,c.id,v_proposal.id
  from (values (v_proposal.sender_id),(v_owner_id)) as recipients(user_id)
  left join public.conversations c on c.proposal_id = v_proposal.id;
  return jsonb_build_object('ok', true, 'expired', true, 'status', 'cancelled');
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
    update public.exchange_proposals
    set status='cancelled'
    where id=v_proposal.id and status='accepted';
    if not found then continue; end if;
    insert into public.notifications(user_id,actor_id,type,title,body,listing_id,conversation_id,proposal_id)
    values
      (v_proposal.sender_id,null,'exchange_proposal','Сделка отменена по таймеру',
       'Час на подтверждение условий истёк. Предложение отменено; объявление снова доступно, если оно активно.',
       v_proposal.listing_id,v_conversation,v_proposal.id),
      (v_listing.user_id,null,'exchange_proposal','Сделка отменена по таймеру',
       'Час на подтверждение условий истёк. Предложение отменено; объявление снова доступно, если оно активно.',
       v_proposal.listing_id,v_conversation,v_proposal.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke execute on function public.expire_unconfirmed_exchange_proposals() from public;
revoke execute on function public.expire_unconfirmed_exchange_proposals() from anon;
revoke execute on function public.expire_unconfirmed_exchange_proposals() from authenticated;
grant execute on function public.expire_unconfirmed_exchange_proposals() to service_role;

select cron.schedule(
  'expire-unconfirmed-exchange-proposals',
  '* * * * *',
  'select public.expire_unconfirmed_exchange_proposals();'
);
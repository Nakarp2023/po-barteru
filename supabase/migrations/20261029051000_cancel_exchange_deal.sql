create or replace function public.cancel_exchange_deal(p_proposal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

revoke all on function public.cancel_exchange_deal(uuid) from public, anon;
grant execute on function public.cancel_exchange_deal(uuid) to authenticated;

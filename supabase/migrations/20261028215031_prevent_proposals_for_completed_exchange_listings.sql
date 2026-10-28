create or replace function public.prevent_proposals_for_completed_exchange_listings()
returns trigger
language plpgsql
set search_path = ''
as $function$
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

revoke all on function public.prevent_proposals_for_completed_exchange_listings() from public, anon, authenticated;

drop trigger if exists prevent_proposals_for_completed_exchange_listings on public.exchange_proposals;
create trigger prevent_proposals_for_completed_exchange_listings
before insert or update of status, listing_id, offered_listing_id on public.exchange_proposals
for each row
execute function public.prevent_proposals_for_completed_exchange_listings();

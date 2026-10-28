create or replace function public.prevent_reactivation_of_completed_exchange_listings()
returns trigger
language plpgsql
set search_path = ''
as $function$
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

revoke all on function public.prevent_reactivation_of_completed_exchange_listings() from public, anon, authenticated;

drop trigger if exists prevent_reactivation_of_completed_exchange_listings on public.listings;
create trigger prevent_reactivation_of_completed_exchange_listings
before update of status on public.listings
for each row
execute function public.prevent_reactivation_of_completed_exchange_listings();

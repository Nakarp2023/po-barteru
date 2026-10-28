-- Preserve listing-related moderation and paid-promotion history when direct DELETE is attempted.
create or replace function public.prevent_delete_listing_with_exchange_history()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if exists (
    select 1 from public.exchange_proposals p
    where p.listing_id = old.id or p.offered_listing_id = old.id
  ) or exists (
    select 1 from public.listing_promotions lp
    where lp.listing_id = old.id
  ) or exists (
    select 1 from public.reports r
    where r.listing_id = old.id
  ) then
    raise exception 'LISTING_HAS_RETAINED_HISTORY: archive the listing instead of deleting it'
      using errcode = '23514';
  end if;

  return old;
end;
$function$;

revoke all on function public.prevent_delete_listing_with_exchange_history() from public, anon, authenticated;

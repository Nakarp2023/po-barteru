-- Preserve accepted/completed exchange records and reviews when a listing owner tries to delete a listing.
create or replace function public.prevent_delete_listing_with_exchange_history()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if exists (
    select 1
    from public.exchange_proposals p
    where (p.listing_id = old.id or p.offered_listing_id = old.id)
      and (
        p.status in ('accepted', 'completed')
        or exists (
          select 1
          from public.exchange_reviews r
          where r.proposal_id = p.id
        )
      )
  ) then
    raise exception 'LISTING_HAS_EXCHANGE_HISTORY: archive the listing instead of deleting it'
      using errcode = '23514';
  end if;

  return old;
end;
$function$;

revoke all on function public.prevent_delete_listing_with_exchange_history() from public, anon, authenticated;

drop trigger if exists prevent_delete_listing_with_exchange_history on public.listings;
create trigger prevent_delete_listing_with_exchange_history
before delete on public.listings
for each row
execute function public.prevent_delete_listing_with_exchange_history();

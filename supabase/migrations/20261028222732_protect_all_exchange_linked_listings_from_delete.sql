-- Keep all exchange-linked listings as historical records, including declined/cancelled proposals.
create or replace function public.prevent_delete_listing_with_exchange_history()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if exists (
    select 1
    from public.exchange_proposals p
    where p.listing_id = old.id
       or p.offered_listing_id = old.id
  ) then
    raise exception 'LISTING_HAS_EXCHANGE_HISTORY: archive the listing instead of deleting it'
      using errcode = '23514';
  end if;

  return old;
end;
$function$;

revoke all on function public.prevent_delete_listing_with_exchange_history() from public, anon, authenticated;

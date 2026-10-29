-- Tighten table privileges in projects with permissive default table grants.
revoke all on table public.support_tickets from anon, public, authenticated;
grant select, insert on table public.support_tickets to authenticated;

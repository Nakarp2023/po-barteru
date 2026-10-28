-- Restrict exchange review table privileges to the operations used by the app.
-- RLS policies continue to control which rows each role can access.
revoke all privileges on table public.exchange_reviews from public, anon, authenticated;

grant select on table public.exchange_reviews to anon;
grant select, insert on table public.exchange_reviews to authenticated;

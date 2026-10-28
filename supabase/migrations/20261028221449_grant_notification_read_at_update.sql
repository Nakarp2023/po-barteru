-- Allow authenticated users to update only the read timestamp on their own notifications.
-- The existing RLS policy "Users can mark own notifications read" limits rows to auth.uid().
revoke update on table public.notifications from public, anon, authenticated;
grant update (read_at) on table public.notifications to authenticated;

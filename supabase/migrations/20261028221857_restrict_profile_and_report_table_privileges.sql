-- Remove direct client privileges that the app does not use.
-- Profile deletion is not a client feature; profile edits use INSERT/UPDATE.
-- Reports may be created/read by their author, but status management is server/admin-side.
revoke delete on table public.profiles from public, anon, authenticated;
revoke update, delete on table public.reports from public, anon, authenticated;

-- Allow each authenticated user to read only their own active/expired subscription rows.
-- The browser selects only plan_code, starts_at, ends_at and status for the profile display.

alter table public.user_subscriptions enable row level security;

drop policy if exists "Users can read own subscriptions" on public.user_subscriptions;
create policy "Users can read own subscriptions"
on public.user_subscriptions
for select
to authenticated
using (user_id = (select auth.uid()));

grant select on public.user_subscriptions to authenticated;

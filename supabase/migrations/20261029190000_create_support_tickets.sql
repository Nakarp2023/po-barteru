-- Real support intake for ПО БАРТЕРУ.
-- Each authenticated user can create tickets and read only their own tickets.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null default 'other'
    check (category in ('account','listing','exchange','payment','safety','technical','other')),
  subject text not null check (char_length(btrim(subject)) between 4 and 120),
  message text not null check (char_length(btrim(message)) between 10 and 5000),
  status text not null default 'open'
    check (status in ('open','in_progress','answered','closed')),
  support_reply text check (support_reply is null or char_length(support_reply) <= 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  replied_at timestamptz
);
create index if not exists support_tickets_user_created_idx
  on public.support_tickets (user_id, created_at desc);
alter table public.support_tickets enable row level security;
revoke all on public.support_tickets from anon, public;
grant select, insert on public.support_tickets to authenticated;
drop policy if exists "Users can read own support tickets" on public.support_tickets;
create policy "Users can read own support tickets"
  on public.support_tickets for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "Users can create own support tickets" on public.support_tickets;
create policy "Users can create own support tickets"
  on public.support_tickets for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- One-time administrator bootstrap lock for Staging.
-- No credentials or bootstrap tokens are stored in this table.
create table if not exists public.admin_bootstrap_claims (
  user_id uuid primary key,
  claimed_at timestamptz not null default now()
);
alter table public.admin_bootstrap_claims enable row level security;
revoke all on public.admin_bootstrap_claims from anon, authenticated;

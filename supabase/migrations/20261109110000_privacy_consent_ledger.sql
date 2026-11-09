-- Privacy consent ledger: server-side append-only record created at Auth user creation.
-- Apply only in the TEST Supabase project first; do not execute against production without review.

create table if not exists public.privacy_consent_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  consent_type text not null check (consent_type = 'personal_data_processing'),
  consent_version text not null,
  consent_text_sha256 text not null,
  accepted_at timestamptz not null default now(),
  source text not null check (source in ('email_password','email_magic_link','phone_otp','unknown')),
  created_at timestamptz not null default now()
);

create index if not exists privacy_consent_log_user_accepted_idx
  on public.privacy_consent_log(user_id, accepted_at desc);

alter table public.privacy_consent_log enable row level security;

drop policy if exists "Users read own privacy consent records" on public.privacy_consent_log;
create policy "Users read own privacy consent records"
  on public.privacy_consent_log for select
  using (auth.uid() = user_id);

-- No client INSERT/UPDATE/DELETE grants or policies: only the trusted trigger writes.
revoke all on public.privacy_consent_log from anon, authenticated;
grant select on public.privacy_consent_log to authenticated;

create or replace function public.log_new_user_privacy_consent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  consent_version text := metadata ->> 'personal_data_consent_version';
  source_value text := metadata ->> 'personal_data_consent_source';
begin
  if metadata ->> 'personal_data_consent' = 'true'
     and consent_version is not null
     and length(consent_version) between 1 and 80 then
    insert into public.privacy_consent_log
      (user_id, consent_type, consent_version, consent_text_sha256, source)
    values (
      new.id,
      'personal_data_processing',
      consent_version,
      'DRAFT_TEXT_HASH_TO_BE_REPLACED_BEFORE_PRODUCTION',
      case when source_value in ('email_password','email_magic_link','phone_otp')
           then source_value else 'unknown' end
    );
  end if;
  return new;
end;
$$;

revoke all on function public.log_new_user_privacy_consent() from public, anon, authenticated;

drop trigger if exists on_auth_user_privacy_consent on auth.users;
create trigger on_auth_user_privacy_consent
  after insert on auth.users
  for each row execute procedure public.log_new_user_privacy_consent();

comment on table public.privacy_consent_log is
  'Append-only server-side record of consent at account creation; draft text hash must be finalized before production.';

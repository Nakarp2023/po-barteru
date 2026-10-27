-- Persist message delivery timestamps and publish receipt updates to Realtime.
alter table public.messages
  add column if not exists delivered_at timestamptz;

update public.messages
   set delivered_at = created_at
 where delivered_at is null;

alter table public.messages
  alter column delivered_at set default now(),
  alter column delivered_at set not null;

create or replace function public.set_message_delivered_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.delivered_at := pg_catalog.now();
  return new;
end;
$$;

drop trigger if exists set_message_delivered_at on public.messages;
create trigger set_message_delivered_at
before insert on public.messages
for each row execute function public.set_message_delivered_at();

revoke all on function public.set_message_delivered_at() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end
$$;

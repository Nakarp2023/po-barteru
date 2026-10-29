alter table public.messages
  add column if not exists delivered_at timestamptz;

update public.messages
   set delivered_at = created_at
 where delivered_at is null;

alter table public.messages
  alter column delivered_at set default now(),
  alter column delivered_at set not null;

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

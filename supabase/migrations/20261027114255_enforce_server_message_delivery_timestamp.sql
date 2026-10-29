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

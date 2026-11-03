-- Compatibility for audit writers/readers using actor_user_id vs actor_id.
alter table public.admin_action_log add column if not exists actor_user_id uuid;

update public.admin_action_log
set actor_user_id = actor_id
where actor_user_id is null;

create or replace function public.sync_admin_action_actor_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.actor_id is null then new.actor_id := new.actor_user_id; end if;
  if new.actor_user_id is null then new.actor_user_id := new.actor_id; end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_admin_action_actor_columns on public.admin_action_log;
create trigger trg_sync_admin_action_actor_columns
before insert or update on public.admin_action_log
for each row execute function public.sync_admin_action_actor_columns();

-- Staging moderation hardening: audit log, listing actions, and report status mapping.
create table if not exists public.admin_action_log (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references auth.users(id),
 target_user_id uuid references auth.users(id), target_listing_id uuid references public.listings(id),
 report_id uuid references public.reports(id), action text not null, details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now());
alter table public.admin_action_log enable row level security;
revoke all on public.admin_action_log from anon,authenticated;

create or replace function public.admin_process_report(p_report_id uuid,p_action text,p_note text default null)
returns public.report_moderation_actions language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_status text; v_row public.report_moderation_actions;
begin
 if v_actor is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin role required' using errcode='42501'; end if;
 if p_action not in ('reviewed','dismissed','resolved','reopened','note') then raise exception 'unsupported action' using errcode='22023'; end if;
 v_status:=case p_action when 'reviewed' then 'reviewing' when 'dismissed' then 'rejected' when 'reopened' then 'reviewing' when 'note' then null else 'resolved' end;
 if v_status is not null then update public.reports set status=v_status where id=p_report_id; if not found then raise exception 'report not found' using errcode='P0002'; end if;
 elsif not exists(select 1 from public.reports where id=p_report_id) then raise exception 'report not found' using errcode='P0002'; end if;
 insert into public.report_moderation_actions(report_id,actor_id,action,note) values(p_report_id,v_actor,p_action,nullif(trim(p_note),'')) returning * into v_row;
 insert into public.admin_action_log(actor_id,report_id,action,details) values(v_actor,p_report_id,'report_'||p_action,jsonb_build_object('note',p_note));
 return v_row;
end $$;
revoke all on function public.admin_process_report(uuid,text,text) from public,anon;
grant execute on function public.admin_process_report(uuid,text,text) to authenticated;

create or replace function public.admin_set_listing_moderation(p_listing_id uuid,p_action text,p_note text default null)
returns public.listings language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_row public.listings;
begin
 if v_actor is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin role required' using errcode='42501'; end if;
 if p_action not in ('hide','restore','archive') then raise exception 'unsupported listing action' using errcode='22023'; end if;
 update public.listings set status=case p_action when 'hide' then 'moderation' when 'restore' then 'active' else 'archived' end,updated_at=now() where id=p_listing_id returning * into v_row;
 if not found then raise exception 'listing not found' using errcode='P0002'; end if;
 insert into public.admin_action_log(actor_id,target_user_id,target_listing_id,action,details) values(v_actor,v_row.user_id,p_listing_id,'listing_'||p_action,jsonb_build_object('note',p_note));
 return v_row;
end $$;
revoke all on function public.admin_set_listing_moderation(uuid,text,text) from public,anon;
grant execute on function public.admin_set_listing_moderation(uuid,text,text) to authenticated;

create or replace function public.admin_process_report(p_report_id uuid, p_action text, p_note text default null)
returns public.report_moderation_actions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_status text;
  v_action public.report_moderation_actions;
begin
  if v_actor is null or coalesce(auth.jwt() -> 'app_metadata' ->> 'role','') <> 'admin' then
    raise exception 'admin role required' using errcode = '42501';
  end if;
  if p_action not in ('reviewed','dismissed','resolved','reopened') then
    raise exception 'unsupported moderation action' using errcode = '22023';
  end if;
  v_status := case when p_action = 'reopened' then 'reviewed' else p_action end;
  update public.reports set status = v_status where id = p_report_id;
  if not found then raise exception 'report not found' using errcode = 'P0002'; end if;
  insert into public.report_moderation_actions(report_id,actor_id,action,note)
  values(p_report_id,v_actor,p_action,nullif(trim(p_note),''))
  returning * into v_action;
  return v_action;
end;
$$;
revoke all on function public.admin_process_report(uuid,text,text) from public, anon;
grant execute on function public.admin_process_report(uuid,text,text) to authenticated;

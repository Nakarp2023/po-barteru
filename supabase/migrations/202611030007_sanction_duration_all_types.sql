-- All non-permanent sanctions can have an optional expiry; temporary ban requires a duration in UI.
create or replace function public.admin_apply_sanction(p_user_id uuid,p_report_id uuid,p_type text,p_reason text,p_duration_hours integer default null,p_severity text default 'low')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_end timestamptz;
begin
 if v_actor is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin role required' using errcode='42501'; end if;
 if p_user_id is null or p_user_id=v_actor then raise exception 'invalid target user' using errcode='22023'; end if;
 if p_type not in ('warning','messages_restricted','listings_restricted','temporary_ban','permanent_ban') then raise exception 'invalid sanction type' using errcode='22023'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'reason required' using errcode='22023'; end if;
 if p_severity not in ('low','medium','high','critical') then raise exception 'invalid severity' using errcode='22023'; end if;
 if p_type='permanent_ban' then v_end:=null;
 elsif p_duration_hours is not null then
   if p_duration_hours<1 or p_duration_hours>8760 then raise exception 'duration must be 1..8760 hours' using errcode='22023'; end if;
   v_end:=now()+make_interval(hours=>p_duration_hours);
 else v_end:=null;
 end if;
 insert into public.user_sanctions(user_id,report_id,actor_id,sanction_type,reason,ends_at) values(p_user_id,p_report_id,v_actor,p_type,trim(p_reason),v_end) returning id into v_id;
 insert into public.user_violations(user_id,report_id,moderator_id,category,severity,note) values(p_user_id,p_report_id,v_actor,p_type,p_severity,trim(p_reason));
 insert into public.admin_action_log(actor_id,target_user_id,report_id,action,details) values(v_actor,p_user_id,p_report_id,'sanction_applied',jsonb_build_object('sanction_id',v_id,'type',p_type,'reason',trim(p_reason),'severity',p_severity,'duration_hours',p_duration_hours,'ends_at',v_end));
 if p_report_id is not null then insert into public.report_moderation_actions(report_id,actor_id,action,note) values(p_report_id,v_actor,'sanction:'||p_type,trim(p_reason)); end if;
 return v_id;
end $$;
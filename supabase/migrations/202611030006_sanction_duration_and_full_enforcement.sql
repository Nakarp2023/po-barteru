-- Staging: consistent duration semantics and complete DB enforcement for user sanctions.
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
 elsif p_type in ('temporary_ban','messages_restricted','listings_restricted') then
   raise exception 'duration required for this sanction' using errcode='22023';
 else v_end:=null; end if;
 insert into public.user_sanctions(user_id,report_id,actor_id,sanction_type,reason,ends_at) values(p_user_id,p_report_id,v_actor,p_type,trim(p_reason),v_end) returning id into v_id;
 insert into public.user_violations(user_id,report_id,moderator_id,category,severity,note) values(p_user_id,p_report_id,v_actor,p_type,p_severity,trim(p_reason));
 insert into public.admin_action_log(actor_id,target_user_id,report_id,action,details) values(v_actor,p_user_id,p_report_id,'sanction_applied',jsonb_build_object('sanction_id',v_id,'type',p_type,'reason',trim(p_reason),'severity',p_severity,'duration_hours',p_duration_hours,'ends_at',v_end));
 if p_report_id is not null then insert into public.report_moderation_actions(report_id,actor_id,action,note) values(p_report_id,v_actor,'sanction:'||p_type,trim(p_reason)); end if;
 return v_id;
end $$;
create or replace function public.enforce_active_user_sanctions()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_restriction text;
begin
 if tg_table_name='messages' then v_user:=new.sender_id; else v_user:=new.user_id; end if;
 select sanction_type into v_restriction from public.user_sanctions s
 where s.user_id=v_user and s.revoked_at is null and s.starts_at<=now() and (s.ends_at is null or s.ends_at>now())
 and s.sanction_type in ('messages_restricted','listings_restricted','temporary_ban','permanent_ban')
 and (s.sanction_type in ('temporary_ban','permanent_ban')
  or (tg_table_name='messages' and s.sanction_type='messages_restricted')
  or (tg_table_name='listings' and s.sanction_type='listings_restricted'))
 order by case s.sanction_type when 'permanent_ban' then 1 when 'temporary_ban' then 2 else 3 end limit 1;
 if v_restriction is not null then raise exception 'Account restriction active: %',v_restriction using errcode='42501'; end if;
 return new;
end $$;
drop trigger if exists trg_enforce_sanctions_messages on public.messages;
create trigger trg_enforce_sanctions_messages before insert on public.messages for each row execute function public.enforce_active_user_sanctions();
drop trigger if exists trg_enforce_sanctions_listings on public.listings;
create trigger trg_enforce_sanctions_listings before insert or update on public.listings for each row execute function public.enforce_active_user_sanctions();
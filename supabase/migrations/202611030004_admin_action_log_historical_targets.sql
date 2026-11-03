-- Resolve missing target_user_id in historical admin audit records.
-- Reports derive the target from reports.reported_user_id; support replies derive it from support_tickets.user_id.
create or replace function public.admin_get_action_log(p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then
  raise exception 'admin access required' using errcode='42501';
 end if;
 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'id',x.id,'actor_id',x.actor_id,'actor_user_id',x.actor_user_id,
   'target_user_id',coalesce(x.target_user_id,r.reported_user_id,t.user_id),
   'target_listing_id',x.target_listing_id,'report_id',x.report_id,
   'action',x.action,'details',x.details,'created_at',x.created_at
  ) order by x.created_at desc)
  from (select * from public.admin_action_log order by created_at desc limit greatest(1,least(coalesce(p_limit,100),500))) x
  left join public.reports r on r.id=x.report_id
  left join public.support_tickets t on t.id=nullif(x.details->>'ticket_id','')::uuid
 ),'[]'::jsonb);
end $$;
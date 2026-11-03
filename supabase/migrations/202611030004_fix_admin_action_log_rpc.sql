-- Fix admin audit RPC: expose the actual actor_id column (not actor_user_id).
drop function public.admin_get_action_log(integer);
create function public.admin_get_action_log(p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'actor_id',l.actor_id,'target_user_id',l.target_user_id,'target_listing_id',l.target_listing_id,'report_id',l.report_id,'action',l.action,'details',l.details,'created_at',l.created_at) order by l.created_at desc) from (select * from public.admin_action_log order by created_at desc limit greatest(1,least(coalesce(p_limit,100),500))) l),'[]'::jsonb);
end $$;
revoke all on function public.admin_get_action_log(integer) from public,anon;
grant execute on function public.admin_get_action_log(integer) to authenticated;

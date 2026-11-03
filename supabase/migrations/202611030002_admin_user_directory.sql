-- Admin user directory and profile overview RPCs (Staging).
create or replace function public.admin_user_overview(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v jsonb;
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin role required' using errcode='42501'; end if;
 select jsonb_build_object('user_id',u.id,'email',u.email,'created_at',u.created_at,'last_sign_in_at',u.last_sign_in_at,
 'profile',to_jsonb(p),'listing_count',(select count(*) from public.listings l where l.user_id=u.id),
 'reports_received',(select count(*) from public.reports r where r.reported_user_id=u.id),
 'violations',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select id,category,severity,note,created_at,report_id from public.user_violations where user_id=u.id order by created_at desc limit 100)x),
 'sanctions',(select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc),'[]'::jsonb) from (select id,sanction_type,reason,starts_at,ends_at,revoked_at,revoke_note,created_at,report_id from public.user_sanctions where user_id=u.id order by created_at desc limit 100)s)
 ) into v from auth.users u left join public.profiles p on p.id=u.id where u.id=p_user_id;
 if v is null then raise exception 'user not found' using errcode='P0002'; end if; return v;
end $$;
revoke all on function public.admin_user_overview(uuid) from public,anon; grant execute on function public.admin_user_overview(uuid) to authenticated;
create or replace function public.admin_search_users(p_query text,p_limit integer default 30)
returns table(user_id uuid,email text,display_name text,created_at timestamptz,active_sanctions bigint,violations bigint)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin role required' using errcode='42501'; end if;
 return query select u.id,u.email,p.display_name,u.created_at,
 (select count(*) from public.user_sanctions s where s.user_id=u.id and s.revoked_at is null and (s.ends_at is null or s.ends_at>now())),
 (select count(*) from public.user_violations v where v.user_id=u.id)
 from auth.users u left join public.profiles p on p.id=u.id
 where nullif(trim(p_query),'') is null or u.email ilike '%'||trim(p_query)||'%' or p.display_name ilike '%'||trim(p_query)||'%'
 order by u.created_at desc limit greatest(1,least(coalesce(p_limit,30),100));
end $$;
revoke all on function public.admin_search_users(text,integer) from public,anon; grant execute on function public.admin_search_users(text,integer) to authenticated;
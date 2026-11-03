create or replace function public.admin_search_users(p_query text, p_limit integer default 30)
returns table(user_id uuid,email text,display_name text,created_at timestamptz,active_sanctions bigint,violations bigint)
language plpgsql security definer set search_path=public,auth,pg_temp as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then
  raise exception 'admin role required' using errcode='42501';
 end if;
 return query
 select u.id::uuid, coalesce(u.email,'')::text, coalesce(p.display_name,'')::text,
        u.created_at::timestamptz,
        coalesce((select count(*) from public.user_sanctions s where s.user_id=u.id and s.revoked_at is null and (s.ends_at is null or s.ends_at>now())),0)::bigint,
        coalesce((select count(*) from public.user_violations v where v.user_id=u.id),0)::bigint
 from auth.users u left join public.profiles p on p.id=u.id
 where nullif(trim(p_query),'') is null or u.id::text ilike '%'||trim(p_query)||'%'
   or coalesce(u.email,'') ilike '%'||trim(p_query)||'%' or coalesce(p.display_name,'') ilike '%'||trim(p_query)||'%'
 order by u.created_at desc limit greatest(1,least(coalesce(p_limit,30),100));
end $$;
grant execute on function public.admin_search_users(text,integer) to authenticated;
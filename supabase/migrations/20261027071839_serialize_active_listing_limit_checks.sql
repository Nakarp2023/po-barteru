create or replace function public.enforce_active_listing_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_limit integer;
  v_active_count integer;
begin
  if new.status <> 'active' then
    return new;
  end if;

  -- Serialize concurrent active-listing writes for the same owner.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text, 0));

  select max(mp.active_listing_limit)
    into v_limit
  from public.user_subscriptions us
  join public.monetization_plans mp on mp.code = us.plan_code
  where us.user_id = new.user_id
    and us.status = 'active'
    and us.starts_at <= now()
    and us.ends_at > now()
    and mp.is_active = true;

  if v_limit is null then
    select mp.active_listing_limit
      into v_limit
    from public.monetization_plans mp
    where mp.code = 'free' and mp.is_active = true
    limit 1;
  end if;

  v_limit := coalesce(v_limit, 3);

  select count(*)
    into v_active_count
  from public.listings l
  where l.user_id = new.user_id
    and l.status = 'active'
    and (tg_op = 'INSERT' or l.id is distinct from new.id);

  if v_active_count >= v_limit then
    raise exception 'ACTIVE_LISTING_LIMIT_REACHED:%', v_limit
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

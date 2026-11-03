-- Extend sanction enforcement to listing edits and exchange proposal actions.
create or replace function public.enforce_sanctions_on_listing_write()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid; v_restriction text;
begin
 v_user:=coalesce(auth.uid(),new.user_id);
 if v_user is distinct from new.user_id then return new; end if;
 select sanction_type into v_restriction from public.user_sanctions s
 where s.user_id=v_user and s.revoked_at is null and s.starts_at<=now() and (s.ends_at is null or s.ends_at>now())
 and s.sanction_type in ('listings_restricted','temporary_ban','permanent_ban')
 order by case s.sanction_type when 'permanent_ban' then 1 when 'temporary_ban' then 2 else 3 end limit 1;
 if v_restriction is not null then raise exception 'Account restriction active: %',v_restriction using errcode='42501'; end if;
 return new;
end $$;
drop trigger if exists trg_enforce_sanctions_listings_write on public.listings;
create trigger trg_enforce_sanctions_listings_write before insert or update on public.listings for each row execute function public.enforce_sanctions_on_listing_write();

create or replace function public.enforce_sanctions_on_exchange_proposal()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_owner uuid; v_restriction text;
begin
 if v_actor is null then return new; end if;
 select user_id into v_owner from public.listings where id=new.listing_id;
 if tg_op='INSERT' then
   if new.sender_id<>v_actor then return new; end if;
   select sanction_type into v_restriction from public.user_sanctions s where s.user_id=v_actor and s.revoked_at is null and s.starts_at<=now() and (s.ends_at is null or s.ends_at>now()) and s.sanction_type in ('temporary_ban','permanent_ban') limit 1;
 else
   if v_actor not in (new.sender_id,v_owner) then return new; end if;
   select sanction_type into v_restriction from public.user_sanctions s where s.user_id=v_actor and s.revoked_at is null and s.starts_at<=now() and (s.ends_at is null or s.ends_at>now()) and s.sanction_type in ('temporary_ban','permanent_ban') limit 1;
 end if;
 if v_restriction is not null then raise exception 'Account restriction active: %',v_restriction using errcode='42501'; end if;
 if tg_op='UPDATE' and v_actor=v_owner and new.status is distinct from old.status then
   select sanction_type into v_restriction from public.user_sanctions s where s.user_id=v_actor and s.revoked_at is null and s.starts_at<=now() and (s.ends_at is null or s.ends_at>now()) and s.sanction_type='temporary_ban' limit 1;
   if v_restriction is not null then raise exception 'Account restriction active: %',v_restriction using errcode='42501'; end if;
 end if;
 return new;
end $$;
drop trigger if exists trg_enforce_sanctions_exchange_proposals on public.exchange_proposals;
create trigger trg_enforce_sanctions_exchange_proposals before insert or update on public.exchange_proposals for each row execute function public.enforce_sanctions_on_exchange_proposal();
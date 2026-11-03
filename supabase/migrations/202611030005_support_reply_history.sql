create table if not exists public.support_ticket_replies (
 id uuid primary key default gen_random_uuid(),
 ticket_id uuid not null references public.support_tickets(id) on delete cascade,
 admin_id uuid not null references auth.users(id),
 reply text not null check(length(trim(reply))>0),
 status text not null check(status in ('open','answered','closed')),
 created_at timestamptz not null default now()
);
create index if not exists support_ticket_replies_ticket_created_idx on public.support_ticket_replies(ticket_id,created_at);
alter table public.support_ticket_replies enable row level security;
revoke all on public.support_ticket_replies from anon, authenticated;
create or replace function public.admin_reply_support_ticket(p_ticket_id uuid,p_reply text,p_status text default 'answered')
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v public.support_tickets;
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin access required' using errcode='42501'; end if;
 if p_status not in ('answered','closed','open') then raise exception 'invalid status'; end if;
 if length(trim(coalesce(p_reply,'')))<1 then raise exception 'reply required'; end if;
 update public.support_tickets set support_reply=trim(p_reply),status=p_status,replied_at=now(),updated_at=now() where id=p_ticket_id returning * into v;
 if not found then raise exception 'ticket not found'; end if;
 insert into public.support_ticket_replies(ticket_id,admin_id,reply,status) values(v.id,auth.uid(),trim(p_reply),p_status);
 insert into public.admin_action_log(actor_id,action,target_user_id,details) values(auth.uid(),'support_ticket_replied',v.user_id,jsonb_build_object('ticket_id',v.id,'status',p_status));
 return to_jsonb(v);
end $$;
create or replace function public.admin_support_ticket_history(p_ticket_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'admin access required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'admin_id',r.admin_id,'reply',r.reply,'status',r.status,'created_at',r.created_at) order by r.created_at asc) from public.support_ticket_replies r where r.ticket_id=p_ticket_id),'[]'::jsonb);
end $$;
revoke all on function public.admin_support_ticket_history(uuid) from public,anon;
grant execute on function public.admin_support_ticket_history(uuid) to authenticated;

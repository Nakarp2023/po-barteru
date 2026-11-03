-- Backfill the last reply stored on legacy support tickets into reply history.
-- Preserve the original replied_at timestamp and attribute legacy replies to the current admin account.
insert into public.support_ticket_replies(ticket_id,admin_id,reply,status,created_at)
select t.id,'d153ce05-b2e8-4913-bb2d-8b69b63db2e4'::uuid,t.support_reply,
       case when t.status in ('open','answered','closed') then t.status else 'answered' end,
       coalesce(t.replied_at,t.updated_at,t.created_at)
from public.support_tickets t
where nullif(trim(t.support_reply),'') is not null
  and not exists(select 1 from public.support_ticket_replies r where r.ticket_id=t.id);

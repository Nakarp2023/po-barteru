-- Align the existing Staging support_tickets checks with Production.
-- The existing Staging test row was checked against these predicates before applying.
alter table public.support_tickets drop constraint if exists support_tickets_message_check;
alter table public.support_tickets drop constraint if exists support_tickets_subject_check;
alter table public.support_tickets add constraint support_tickets_message_check
  check (char_length(btrim(message)) >= 10 and char_length(btrim(message)) <= 5000);
alter table public.support_tickets add constraint support_tickets_subject_check
  check (char_length(btrim(subject)) >= 4 and char_length(btrim(subject)) <= 120);
alter table public.support_tickets add constraint support_tickets_support_reply_check
  check (support_reply is null or char_length(support_reply) <= 5000);

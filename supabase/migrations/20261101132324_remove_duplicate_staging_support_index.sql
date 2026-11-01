-- Remove the duplicate support-ticket index that existed only in Staging.
-- Keep support_tickets_user_created_idx, matching Production.
drop index if exists public.support_tickets_user_id_created_at_idx;

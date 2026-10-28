-- Trigger functions are invoked by PostgreSQL triggers, not directly through the client API.
-- Remove default client execution grants from the exchange-proposal status guard.
-- This does not change trigger execution or exchange status logic.
REVOKE EXECUTE ON FUNCTION public.guard_exchange_proposal_status_transition()
  FROM PUBLIC, anon, authenticated;

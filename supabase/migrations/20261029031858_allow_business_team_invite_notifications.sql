-- Keep notification types aligned with the Business team invitation flow.
-- This migration has already been applied in production as 20261029031858.
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'exchange_proposal',
    'message',
    'favorite',
    'exchange_review',
    'business_team_invite'
  ]));

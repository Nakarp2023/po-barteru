-- Run the history guard with the function owner's privileges so RLS cannot hide
-- related proposals, promotions, or reports from the DELETE protection check.
CREATE OR REPLACE FUNCTION public.prevent_delete_listing_with_exchange_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.exchange_proposals p
    WHERE p.listing_id = OLD.id OR p.offered_listing_id = OLD.id
  ) OR EXISTS (
    SELECT 1
    FROM public.listing_promotions lp
    WHERE lp.listing_id = OLD.id
  ) OR EXISTS (
    SELECT 1
    FROM public.reports r
    WHERE r.listing_id = OLD.id
  ) THEN
    RAISE EXCEPTION 'LISTING_HAS_RETAINED_HISTORY: archive the listing instead of deleting it'
      USING ERRCODE = '23514';
  END IF;

  RETURN OLD;
END;
$function$;

-- Trigger invocation does not require client EXECUTE privileges. Keep the
-- function unavailable as a direct RPC to all API-facing roles.
REVOKE ALL ON FUNCTION public.prevent_delete_listing_with_exchange_history() FROM PUBLIC, anon, authenticated;

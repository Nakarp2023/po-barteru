-- Stabilize admin audit trigger: actor_id is canonical; legacy alias sync caused row-field errors.
CREATE OR REPLACE FUNCTION public.sync_admin_action_actor_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  RETURN NEW;
END;
$$;

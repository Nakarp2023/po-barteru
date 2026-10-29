# Supabase security audit addendum — 2026-10-29

## Private exchange-review helper

Observed in production catalog:
- `private.exchange_review_is_published(uuid, uuid, uuid, timestamptz)` is SECURITY DEFINER with an empty `search_path`.
- EXECUTE is granted to `anon` and `authenticated`; both roles also have USAGE on schema `private`.
- Its body returns true when the supplied timestamp is older than 24 hours, or when a reciprocal review exists for the supplied proposal and reviewer pair.
- Supabase documentation says custom schemas are reachable through the Data API only when listed under API Settings → Exposed schemas. The database setting could not be read via the available SQL interface, so whether `private` is exposed remains unverified.

Recommendation: in Supabase Dashboard → API Settings, verify that `private` is NOT in Exposed schemas. Keep the schema private; do not revoke the function grants until the review SELECT policy has been tested, because the policy calls this helper. If `private` is exposed, remove it from the exposed list if no API client requires it, then re-test reviews. If it must remain exposed, remove client EXECUTE only after confirming the policy still evaluates correctly (for example, by testing with authenticated and anonymous clients in a safe test environment).

## Secrets in migration history

Production migration `20261026223425_configure_push_delivery_secrets_and_realtime` contains a literal private VAPID key which matches the currently stored Vault value. The literal is not reproduced here or committed to Git. The original migration history should be treated as sensitive. Assess VAPID key rotation separately, with a rollout plan for existing push subscriptions; do not rotate automatically as part of repository cleanup.

## Advisor findings

- Leaked-password protection is disabled. Enable it in Authentication → Providers → Email → Password security → Leaked password protection. Documentation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Security Advisor flags five authenticated SECURITY DEFINER RPCs used by the app: `confirm_exchange_completed`, `confirm_exchange_terms`, `mark_conversation_messages_read`, `respond_to_exchange_proposal`, `update_exchange_terms`. Static inspection found participant/state checks; retain their grants unless negative tests prove a flaw or the frontend no longer requires them.
- `public.payment_webhook_events` has RLS enabled and no client grants/policies; that is consistent with a server-only webhook ledger. Do not add client policies.
- Performance Advisor reports 19 unused-index warnings. Do not drop indexes based solely on usage counters, particularly in a young/low-traffic project.

## Safety boundary

No production DDL, grant changes, migration replay, payment status changes, subscription changes, or exchange status changes were performed during this audit.

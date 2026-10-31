# Supabase security audit addendum — 2026-10-31

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
- Security Advisor currently flags six authenticated SECURITY DEFINER RPCs: `cancel_exchange_deal`, `confirm_exchange_completed`, `confirm_exchange_terms`, `mark_conversation_messages_read`, `respond_to_exchange_proposal`, and `update_exchange_terms`. The additional finding is `cancel_exchange_deal`. Read-only catalog inspection confirms all six use an empty `search_path`; their bodies must still be verified against participant, ownership, and state-transition abuse cases in a safe staging environment. Do not revoke grants in production until the app's required flows and negative tests have been checked.
- `public.payment_webhook_events` has RLS enabled and no client grants/policies; that is consistent with a server-only webhook ledger. Do not add client policies.
- Performance Advisor reports 18 unused-index warnings as of 2026-10-31. Do not drop indexes based solely on usage counters, particularly in a young/low-traffic project.

## 2026-10-31 verification update

- Supabase project remains `ACTIVE_HEALTHY` on PostgreSQL 17.11.0.003.
- Security Advisor still reports the server-only `public.payment_webhook_events` table as RLS-enabled with no policies. This is intentional: do not add client access.
- Leaked-password protection remains disabled. Enable it through Authentication → Providers → Email → Password security only after confirming the user-facing password/reset flow in a test environment; the setting itself is a Dashboard Auth control and was not changed here.
- Read-only policy inventory confirms support tickets have authenticated-only SELECT/INSERT policies scoped to `auth.uid() = user_id`; the user-facing table privileges are SELECT/INSERT only. Support staff reply/update path must remain server-side.
- The `private` schema exposure setting remains unverified. Confirm in Dashboard → API Settings → Exposed schemas that `private` is not exposed. Do not change the helper's EXECUTE grants until review reads are tested in staging.
- The app's live RLS policy inventory was inspected read-only. This is not a substitute for two-account negative tests; those require a safe staging project and real authenticated sessions.

## Safety boundary

No production DDL, grant changes, migration replay, Auth setting changes, payment status changes, subscription changes, or exchange status changes were performed during this audit.

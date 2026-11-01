# PO БАРТЕРУ — Staging database

This directory documents the isolated Supabase Staging environment. It is intentionally separate from the Production database.

- Staging project ref: `noiryqvoohqrfmemfnne`
- Production project ref: `qxsnjksepzmpsifpxyea`
- Staging frontend branch: `work/integrated-staging-navigation-no-gestures`
- Staging frontend must use only the Staging project URL and publishable key.
- Staging CLI and schema work must use `supabase/staging/project-connection.txt`; the root `supabase/project-connection.txt` points to Production and must not be used for Staging operations.

## Safety rules

1. Never point the Staging frontend at Production Supabase.
2. Never apply files from this branch to Production.
3. Never copy Production auth users, listings, messages, exchange records, payment orders, webhook events, or storage objects into Staging.
4. Payment provider Edge Functions, webhook secrets, Vault secrets, VAPID secrets, and push dispatch are intentionally excluded from this baseline.
5. Real payments and payment-state transitions must remain disabled during Staging tests.
6. The `delete-listing` Edge Function is deployed to Staging with JWT verification and server-side ownership checks.
7. The pre-existing `support-telegram-notify`, `support-telegram-webhook`, and `support-telegram-setup` functions are present. Do not invoke support notification or webhook setup during testing until the Telegram secrets and destination are confirmed; the notification function still has an older preview-domain CORS origin.
8. Keep the navigation-only PR separate from this branch. The current Staging branch is not a merge candidate for `main`.

## Schema baseline

The following Staging migrations were generated from a read-only Production catalog snapshot and applied only to the Staging project:

- `20261101132027_restore_application_tables_and_indexes.sql`
- `20261101132116_restore_application_security_and_runtime_schema.sql`
- `20261101132211_align_support_ticket_constraints_with_production.sql`
- `20261101132324_remove_duplicate_staging_support_index.sql`
- `20261101132423_seed_staging_monetization_catalog.sql`

The first two Staging-only bootstrap migrations (`20261101043229` and `20261101043252`) predate this repository snapshot. Their original SQL source was not present in the repository; do not invent or replay reconstructed versions. Their current effects are included in the schema comparison and baseline.

## Intentional Staging differences

- No Production user or transactional data is copied. Newly created application tables start empty.
- The pre-existing Staging support ticket test row is preserved.
- The public monetization catalog is seeded with plan definitions only; no orders or subscription states are seeded.
- The Vault-backed VAPID functions and the notification push-dispatch trigger are omitted to prevent external push side effects.
- The Production cron schedule is not installed in Staging.

Before adding a new Staging migration, create and review the SQL file here, then apply it to Staging only. Compare schema and security advisors after each change.

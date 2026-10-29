# Supabase migration history inventory

Checked against production `supabase_migrations.schema_migrations` on 2026-10-29.

## Current state

- Production migration records: 89.
- SQL files under `supabase/migrations`: 17.
- Existing file versions match production history.
- Missing standalone SQL files: 72.
- This inventory is documentation only. It does not replay or apply migrations.

## Recovery constraints

Do not run `supabase db push`, replay `supabase/schema.sql`, or apply historical migrations to the existing production database to repair this repository inventory. Production already contains these changes.

Historical migration `20261026223425_configure_push_delivery_secrets_and_realtime` contains a literal private VAPID key that matches the current Vault value. Do not copy that literal into Git. If the historical SQL is restored to version control, replace the literal with a safe placeholder and document that the file is a redacted historical record, not a replayable migration. Evaluate key rotation separately because changing the VAPID key pair can require existing clients to resubscribe.

## Missing versions

| Version | Migration |
|---|---|
| 20261026204703 | listing_image_storage |
| 20261026214613 | add_in_app_notifications |
| 20261026222838 | push_notification_subscriptions |
| 20261026223425 | configure_push_delivery_secrets_and_realtime (contains private-key literal; redact before version control) |
| 20261026224642 | enable_database_triggered_push_delivery |
| 20261026230042 | add_secure_exchange_proposal_responses |
| 20261026233518 | add_exchange_agreement_confirmations |
| 20261026233551 | add_secure_exchange_terms_workflow |
| 20261026235537 | allow_users_to_delete_own_notifications |
| 20261027003236 | add_monetization_foundation |
| 20261027010736 | prevent_duplicate_pending_monetization_orders |
| 20261027011044 | add_server_only_paid_order_activation |
| 20261027011434 | add_payment_webhook_event_ledger |
| 20261027042907 | allow_users_to_delete_own_messages |
| 20261027043424 | user_scoped_chat_and_exchange_hiding |
| 20261027044911 | audit_security_function_grants_and_fk_indexes |
| 20261027045137 | optimize_rls_auth_uid_evaluation |
| 20261027064554 | allow_public_read_active_listing_promotions |
| 20261027073955 | public_active_listing_subscriptions |
| 20261027075926 | listing_view_analytics |
| 20261027080141 | listing_view_stats_rpc |
| 20261027080227 | pro_saved_search_notifications |
| 20261027080355 | pro_plus_promotion_credits |
| 20261027080434 | business_team_access |
| 20261027080543 | restrict_internal_trigger_function_execution |
| 20261027080631 | restrict_view_analytics_to_paid_tiers |
| 20261027080709 | isolate_paid_feature_privileged_rpcs |
| 20261027080754 | prevent_overlapping_subscription_tiers |
| 20261027080845 | expire_promotion_credits_with_subscription |
| 20261027080903 | saved_search_text_matching |
| 20261027080949 | saved_search_query_text_matching |
| 20261027081026 | tighten_view_tracking_and_notify_restored_listings |
| 20261027085521 | prevent_duplicate_open_monetization_orders |
| 20261027091514 | restrict_anon_active_listing_subscriptions |
| 20261027093914 | restrict_active_listing_subscription_rpc_to_service_role |
| 20261027093938 | reject_null_exchange_decisions_and_terms |
| 20261027094428 | tighten_conversation_insert_policy |
| 20261027094854 | restrict_exchange_proposal_direct_mutations |
| 20261027095210 | restrict_direct_chat_table_mutations |
| 20261027095340 | revoke_message_update_privilege |
| 20261027095351 | remove_anonymous_message_access |
| 20261027095603 | restrict_notification_creation_to_trusted_triggers |
| 20261027095934 | remove_anonymous_notification_table_access |
| 20261027100009 | reduce_anonymous_table_privileges |
| 20261027100258 | limit_notification_updates_to_read_state |
| 20261027100411 | remove_unneeded_authenticated_table_privileges |
| 20261027101132 | validate_exchange_confirmation_listing |
| 20261027101139 | validate_exchange_completion_listing |
| 20261027101146 | validate_exchange_terms_listing |
| 20261027101152 | validate_exchange_proposal_participants |
| 20261027101501 | optimize_conversation_insert_rls |
| 20261027103054 | unique_provider_payment_reference |
| 20261027103115 | require_positive_monetization_order_amount |
| 20261027103446 | remove_stale_exchange_proposal_update_policy |
| 20261027103525 | validate_exchange_proposal_insert_targets |
| 20261027103840 | validate_active_listings_on_proposal_acceptance |
| 20261027103851 | lock_exchange_listings_in_stable_order |
| 20261027104111 | restrict_exchange_proposal_initial_state |
| 20261027104433 | bound_exchange_surcharge_and_terms_version |
| 20261027110645 | archive_listings_after_completed_exchange |
| 20261027110704 | fix_archive_only_active_exchange_listings |
| 20261027123030 | exchange_reviews_and_ratings |
| 20261027123053 | fix_exchange_review_policy_scope |
| 20261027123530 | allow_exchange_review_notifications |
| 20261027124849 | add_public_review_name_preference |
| 20261027131019 | blind_exchange_reviews_with_24h_release |
| 20261027131748 | secure_blind_review_visibility_function |
| 20261027131902 | optimize_exchange_review_policy_and_index |
| 20261027144512 | prevent_multiple_accepted_exchange_proposals |
| 20261027145212 | guard_exchange_proposal_status_transitions |
| 20261028171618 | add_listing_subcategory |
| 20261028173006 | add_listing_region |

## Security follow-ups (not applied here)

1. Enable leaked-password protection in Supabase Dashboard → Authentication → Providers → Email → Password security.
2. Verify whether the `private` schema is included in PostgREST's exposed schemas. The role `anon` and `authenticated` currently have USAGE on `private`, and both can EXECUTE `private.exchange_review_is_published(...)`; do not revoke privileges until confirming policy evaluation and schema exposure.
3. Keep the five participant-checked exchange/chat SECURITY DEFINER RPCs available unless a reviewed change proves the client no longer needs them.
4. Keep `public.payment_webhook_events` without client policies: RLS is enabled and direct anon/authenticated table grants were not found.

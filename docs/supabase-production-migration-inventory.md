# Supabase production migration inventory

**Project:** `qxsnjksepzmpsifpxyea`  
**Last checked:** 2026-10-31 (UTC; reconciled against 99 production records)  
**Source:** live Supabase migration history returned by the Supabase migration-list API.

This is an inventory of migration records currently present in production. It is **not** a claim that every historical migration has a corresponding SQL file in this repository, nor is it a reconstruction of missing SQL. The production history contains records for which no separate migration file was found in the prior repository audit. Keep this inventory updated when migrations are applied.

> Safety: do not replay historical migrations or run `supabase db push` merely to reconcile history. Compare exact versions and SQL contents first. Production migration history includes a private VAPID key in one historical migration; never copy secret values into this document or Git.

| Version | Production migration name |
|---|---|
| 20261026204703 | listing_image_storage |
| 20261026214613 | add_in_app_notifications |
| 20261026222838 | push_notification_subscriptions |
| 20261026223425 | configure_push_delivery_secrets_and_realtime |
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
| 20261027071751 | enforce_active_listing_plan_limits |
| 20261027071839 | serialize_active_listing_limit_checks |
| 20261027072118 | allow_users_to_read_own_subscription_status |
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
| 20261027113823 | add_message_read_receipts |
| 20261027114216 | add_persisted_message_delivery_status |
| 20261027114255 | enforce_server_message_delivery_timestamp |
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
| 20261028214848 | prevent_reactivation_of_completed_exchange_listings |
| 20261028215031 | prevent_proposals_for_completed_exchange_listings |
| 20261028215819 | revoke_client_execute_on_exchange_status_trigger |
| 20261028221317 | restrict_exchange_review_table_privileges |
| 20261028221449 | grant_notification_read_at_update |
| 20261028221553 | notify_exchange_review_server_side |
| 20261028221857 | restrict_profile_and_report_table_privileges |
| 20261028222317 | prevent_delete_listings_with_exchange_history |
| 20261028222732 | protect_all_exchange_linked_listings_from_delete |
| 20261028222902 | protect_listing_promotion_and_report_history |
| 20261029020904 | run_listing_history_guard_as_definer |
| 20261029031858 | allow_business_team_invite_notifications |
| 20261029045731 | cancel_exchange_deal |
| 20261029050049 | exchange_confirmation_timeout |
| 20261029053340 | hide_permanently_deleted_exchange_listings |
| 20261029055414 | enable_exchange_proposal_realtime |
| 20261029065136 | close_chat_after_exchange_and_remind_contacts |
| 20261029065219 | require_live_exchange_for_chat_messages |
| 20261029065605 | notify_exchange_terms_changes_server_side |
| 20261029184414 | create_support_tickets |
| 20261029184427 | restrict_support_ticket_grants |

## Repository source-file reconciliation

**Checked:** 2026-10-31 against the live production migration history and the complete GitHub `supabase/migrations/` directory listing.

- Production migration records: **99**.
- SQL migration files currently present in the repository: **21**.
- Production versions with an exact matching SQL filename: **17**.
- Production versions without an exact matching SQL filename: **82**.
- Repository SQL versions absent from production history: **4**.

The four repository files whose version prefixes are not present in production are not automatically considered deployable. They have production counterparts under different versions (`cancel_exchange_deal`, `exchange_confirmation_timeout`, `create_support_tickets`, and `restrict_support_ticket_grants`). Their SQL content and deployed definitions must be compared before classifying them as duplicates, renamed versions, or divergent sources. Do not apply them.

The missing files below are source-recovery work items only. **Do not recreate SQL from migration names, replay these migrations, or run `supabase db push` as a way to reconcile them.** Recover originals from a trusted backup/commit/archive where available; otherwise document each as unavailable. Production remains the authority for current live state, not for the missing original source text.

| Missing production SQL version | Recorded production migration name |
|---|---|
| 20261026204703 | listing_image_storage |
| 20261026214613 | add_in_app_notifications |
| 20261026222838 | push_notification_subscriptions |
| 20261026223425 | configure_push_delivery_secrets_and_realtime |
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
| 20261029031858 | allow_business_team_invite_notifications |
| 20261029045731 | cancel_exchange_deal |
| 20261029050049 | exchange_confirmation_timeout |
| 20261029053340 | hide_permanently_deleted_exchange_listings |
| 20261029055414 | enable_exchange_proposal_realtime |
| 20261029065136 | close_chat_after_exchange_and_remind_contacts |
| 20261029065219 | require_live_exchange_for_chat_messages |
| 20261029065605 | notify_exchange_terms_changes_server_side |
| 20261029184414 | create_support_tickets |
| 20261029184427 | restrict_support_ticket_grants |

## Bootstrap schema warning

The repository also contains `supabase/schema.sql`, a small initial/bootstrap schema. It is **not a canonical production restore script** and must not be run against the live database as a shortcut for recovering missing migrations.

The current file defines only the early core tables and contains older behavior that differs from the hardened production state, including cascading deletion from users/listings into exchange-related records and direct client mutation policies for exchange proposals. It does not represent the full current application schema (for example, the later monetization, notification, review, and business-team features are absent).

For recovery, use a trusted production schema snapshot or a verified sequence of original migrations. Compare against the live database before applying any DDL. Never use this bootstrap file to overwrite production policies or constraints.

## Follow-up checks

- Compare each production version above with the SQL files in `supabase/migrations/` by exact version prefix.
- For every unmatched production record, classify it as: missing historical SQL, intentionally consolidated/superseded file, or repository omission. Do not invent SQL to fill gaps.
- For each local SQL migration not listed above, determine whether it is unapplied, intentionally excluded, or belongs to a different environment before any deployment.
- Keep credentials, webhook secrets, private VAPID keys, and other secret literals out of source control and documentation.

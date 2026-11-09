-- Optimize the consent ledger's own-user RLS predicate.
drop policy if exists "Users read own privacy consent records" on public.privacy_consent_log;
create policy "Users read own privacy consent records"
  on public.privacy_consent_log for select
  using ((select auth.uid()) = user_id);

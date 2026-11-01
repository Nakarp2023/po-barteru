create index if not exists exchange_proposals_expiry_scan_idx
on public.exchange_proposals (accepted_at)
where status = 'accepted'
  and accepted_at is not null
  and not (sender_confirmed_terms and owner_confirmed_terms)
  and sender_completed_at is null
  and owner_completed_at is null;
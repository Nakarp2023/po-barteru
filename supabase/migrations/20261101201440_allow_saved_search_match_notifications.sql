alter table public.notifications
  drop constraint if exists notifications_type_check;

alter table public.notifications
  add constraint notifications_type_check
  check (
    type = any (
      array[
        'exchange_proposal',
        'message',
        'favorite',
        'exchange_review',
        'business_team_invite',
        'exchange_contacts',
        'exchange_terms',
        'saved_search_match'
      ]::text[]
    )
  );

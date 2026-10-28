-- Create the review notification on the server, not from the browser client.
create or replace function public.notify_exchange_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.reviewer_id is null
     or new.reviewed_user_id is null
     or new.reviewer_id = new.reviewed_user_id then
    return new;
  end if;

  insert into public.notifications
    (user_id, actor_id, type, title, body, proposal_id)
  values
    (new.reviewed_user_id,
     new.reviewer_id,
     'exchange_review',
     'Новый отзыв о тебе',
     'Отзыв о завершённом обмене будет опубликован после встречного отзыва или через 24 часа.',
     new.proposal_id);

  return new;
end;
$function$;

drop trigger if exists exchange_review_notification on public.exchange_reviews;
create trigger exchange_review_notification
after insert on public.exchange_reviews
for each row execute function public.notify_exchange_review();

revoke all on function public.notify_exchange_review() from public, anon, authenticated;

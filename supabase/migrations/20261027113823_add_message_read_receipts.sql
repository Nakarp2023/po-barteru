alter table public.messages add column if not exists read_at timestamptz;
create index if not exists messages_conversation_sender_read_idx on public.messages (conversation_id, sender_id, read_at, created_at);
create or replace function public.mark_conversation_messages_read(p_conversation_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_count integer;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.participant_one = v_user_id or c.participant_two = v_user_id)
  ) then raise exception 'Conversation not found or access denied'; end if;
  update public.messages m
     set read_at = now()
   where m.conversation_id = p_conversation_id
     and m.sender_id <> v_user_id
     and m.read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.mark_conversation_messages_read(uuid) from public, anon;
grant execute on function public.mark_conversation_messages_read(uuid) to authenticated;

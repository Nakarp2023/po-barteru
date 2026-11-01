drop policy if exists "Profiles are viewable" on public.profiles;

create policy "Profiles are viewable according to name visibility"
on public.profiles
for select
to anon, authenticated
using (
  id = (select auth.uid())
  or show_public_name is true
);

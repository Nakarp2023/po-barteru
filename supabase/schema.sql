-- ПО БАРТЕРУ: начальная схема Supabase/PostgreSQL
-- Запускать в Supabase SQL Editor после создания проекта.
-- Пользовательские данные не добавляются автоматически; RLS включён.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Пользователь',
  city text,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 100),
  description text not null default '' check (char_length(description) <= 2000),
  category text not null default 'Другое',
  city text not null,
  want text not null,
  estimated_value numeric(12,2) check (estimated_value is null or estimated_value >= 0),
  image_urls text[] not null default '{}',
  status text not null default 'active' check (status in ('active','reserved','exchanged','archived','moderation')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists listings_status_created_idx on public.listings(status, created_at desc);
create index if not exists listings_city_idx on public.listings(city);
create index if not exists listings_category_idx on public.listings(category);

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create table if not exists public.exchange_proposals (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null default '' check (char_length(message) <= 2000),
  offered_listing_id uuid references public.listings(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled','completed')),
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid unique references public.exchange_proposals(id) on delete set null,
  participant_one uuid not null references auth.users(id) on delete cascade,
  participant_two uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (participant_one <> participant_two)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 3 and 1000),
  status text not null default 'new' check (status in ('new','reviewing','resolved','rejected')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.exchange_proposals enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;

-- Публичный просмотр только активных объявлений; владелец управляет своими.
create policy "Profiles are viewable" on public.profiles for select using (true);
create policy "Users insert own profile" on public.profiles for insert with check (auth.uid() = id);
create policy "Users update own profile" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "Active listings are public" on public.listings for select using (status = 'active' or auth.uid() = user_id);
create policy "Users create own listings" on public.listings for insert with check (auth.uid() = user_id);
create policy "Owners update own listings" on public.listings for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Owners delete own listings" on public.listings for delete using (auth.uid() = user_id);

create policy "Users view own favorites" on public.favorites for select using (auth.uid() = user_id);
create policy "Users add own favorites" on public.favorites for insert with check (auth.uid() = user_id);
create policy "Users remove own favorites" on public.favorites for delete using (auth.uid() = user_id);

create policy "Proposal participants can view" on public.exchange_proposals for select using (auth.uid() = sender_id or auth.uid() = (select user_id from public.listings where id = listing_id));
create policy "Users create proposals as themselves" on public.exchange_proposals for insert with check (auth.uid() = sender_id);
create policy "Proposal sender can update" on public.exchange_proposals for update using (auth.uid() = sender_id) with check (auth.uid() = sender_id);

create policy "Participants view conversations" on public.conversations for select using (auth.uid() = participant_one or auth.uid() = participant_two);
create policy "Participants create conversations" on public.conversations for insert with check (auth.uid() = participant_one or auth.uid() = participant_two);
create policy "Participants view messages" on public.messages for select using (exists (select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.participant_one,c.participant_two)));
create policy "Participants send own messages" on public.messages for insert with check (auth.uid() = sender_id and exists (select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.participant_one,c.participant_two)));

create policy "Users view own reports" on public.reports for select using (auth.uid() = reporter_id);
create policy "Users create own reports" on public.reports for insert with check (auth.uid() = reporter_id);

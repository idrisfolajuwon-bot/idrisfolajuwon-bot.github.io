-- CHATDUN AI + Arena first live stage
-- Applied to Supabase project fgkylbebokqcviqcbmoi on 2026-11-23.
-- AI conversations are owner-only. Arena spaces are curated/read-only; membership rows are private per user.

create table if not exists public.chatdun_ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null,
  title text not null default 'New conversation' check (char_length(title) between 1 and 80),
  messages jsonb not null default '[]'::jsonb check (jsonb_typeof(messages) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chatdun_ai_conversations_user_conversation_unique unique (user_id, conversation_id),
  constraint chatdun_ai_conversations_size_check check (octet_length(messages::text) <= 500000)
);
create index if not exists chatdun_ai_conversations_user_updated_idx
  on public.chatdun_ai_conversations (user_id, updated_at desc);
alter table public.chatdun_ai_conversations enable row level security;
create policy "CHATDUN AI users read own conversations" on public.chatdun_ai_conversations
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "CHATDUN AI users create own conversations" on public.chatdun_ai_conversations
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "CHATDUN AI users update own conversations" on public.chatdun_ai_conversations
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "CHATDUN AI users delete own conversations" on public.chatdun_ai_conversations
  for delete to authenticated using ((select auth.uid()) = user_id);
revoke all on public.chatdun_ai_conversations from public, anon, authenticated;
grant select, insert, update, delete on public.chatdun_ai_conversations to authenticated;

create table if not exists public.chatdun_arena_spaces (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  category text not null,
  description text not null,
  icon text not null default '✦',
  status text not null default 'active' check (status in ('active','paused')),
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);
alter table public.chatdun_arena_spaces enable row level security;
create policy "CHATDUN Arena members discover active spaces" on public.chatdun_arena_spaces
  for select to authenticated using (status = 'active');
revoke all on public.chatdun_arena_spaces from public, anon, authenticated;
grant select on public.chatdun_arena_spaces to authenticated;

create table if not exists public.chatdun_arena_members (
  space_id uuid not null references public.chatdun_arena_spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (space_id, user_id)
);
create index if not exists chatdun_arena_members_user_idx
  on public.chatdun_arena_members (user_id, joined_at desc);
alter table public.chatdun_arena_members enable row level security;
create policy "CHATDUN Arena users see own memberships" on public.chatdun_arena_members
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "CHATDUN Arena users join as themselves" on public.chatdun_arena_members
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "CHATDUN Arena users leave own memberships" on public.chatdun_arena_members
  for delete to authenticated using ((select auth.uid()) = user_id);
revoke all on public.chatdun_arena_members from public, anon, authenticated;
grant select, insert, delete on public.chatdun_arena_members to authenticated;

insert into public.chatdun_arena_spaces (slug,title,category,description,icon,sort_order)
values
 ('study-hall','Study Hall','Learning','Ask questions, share study goals and learn difficult topics together.','📚',10),
 ('tech-makers','Tech & Makers','Technology','Explore AI, gadgets, coding and ideas for useful projects.','⚙️',20),
 ('gaming-lounge','Gaming Lounge','Gaming','Talk about games, updates, teamwork and friendly competition.','🎮',30),
 ('music-culture','Music & Culture','Culture','Discover sounds, artists, entertainment and culture from around the world.','🎧',40),
 ('creative-corner','Creative Corner','Creativity','Share writing, design ideas, photography and original creations.','🎨',50),
 ('sports-fans','Sports Fans','Sports','Discuss teams, players, matches and the moments fans enjoy.','🏟️',60)
on conflict (slug) do nothing;

-- The SQL above was applied directly through the Supabase SQL execution tool.
-- Keep this file as the repository's schema reference; it is not a CLI-generated migration.

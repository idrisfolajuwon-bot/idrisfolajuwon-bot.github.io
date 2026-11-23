-- CHATDUN Arena private live-video pilot.
-- One host and one invited viewer, limited to an existing one-to-one conversation.
-- The browser carries media with WebRTC; Supabase Realtime carries only connection signals.
-- Applied directly to the Supabase project; this file is a reproducible schema reference.

create table if not exists public.chatdun_arena_live_rooms (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.chatdun_conversations(id) on delete cascade,
  host_id uuid not null references auth.users(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'live' check (status in ('live','ended')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '45 minutes'),
  ended_at timestamptz,
  constraint chatdun_arena_live_distinct_users check (host_id <> viewer_id),
  constraint chatdun_arena_live_expiry check (expires_at <= created_at + interval '1 hour')
);

create unique index if not exists chatdun_arena_one_live_room_per_conversation
on public.chatdun_arena_live_rooms(conversation_id)
where status = 'live';

create or replace function private.chatdun_arena_is_conversation_pair(
  p_conversation_id uuid, p_host_id uuid, p_viewer_id uuid
) returns boolean
language sql stable security definer set search_path = pg_catalog
as $$
  select p_host_id <> p_viewer_id
    and exists (
      select 1 from public.chatdun_conversations c
      where c.id = p_conversation_id and c.is_group = false
    )
    and exists (
      select 1 from public.chatdun_members m
      where m.conversation_id = p_conversation_id and m.user_id = p_host_id
    )
    and exists (
      select 1 from public.chatdun_members m
      where m.conversation_id = p_conversation_id and m.user_id = p_viewer_id
    )
    and not exists (
      select 1 from public.chatdun_blocks b
      where (b.blocker_id = p_host_id and b.blocked_id = p_viewer_id)
         or (b.blocker_id = p_viewer_id and b.blocked_id = p_host_id)
    );
$;

alter table public.chatdun_arena_live_rooms enable row level security;

drop policy if exists "CHATDUN Arena live participants read rooms" on public.chatdun_arena_live_rooms;
create policy "CHATDUN Arena live participants read rooms"
on public.chatdun_arena_live_rooms for select to authenticated
using (
  (host_id = (select auth.uid()) or viewer_id = (select auth.uid()))
  and private.chatdun_arena_is_conversation_pair(conversation_id, host_id, viewer_id)
);

drop policy if exists "CHATDUN Arena hosts create private rooms" on public.chatdun_arena_live_rooms;
create policy "CHATDUN Arena hosts create private rooms"
on public.chatdun_arena_live_rooms for insert to authenticated
with check (
  host_id = (select auth.uid())
  and status = 'live'
  and ended_at is null
  and expires_at > now()
  and private.chatdun_arena_is_conversation_pair(conversation_id, host_id, viewer_id)
);

drop policy if exists "CHATDUN Arena participants end rooms" on public.chatdun_arena_live_rooms;
create policy "CHATDUN Arena participants end rooms"
on public.chatdun_arena_live_rooms for update to authenticated
using (
  (host_id = (select auth.uid()) or viewer_id = (select auth.uid()))
  and status = 'live'
  and private.chatdun_arena_is_conversation_pair(conversation_id, host_id, viewer_id)
)
with check (
  (host_id = (select auth.uid()) or viewer_id = (select auth.uid()))
  and status = 'ended'
  and ended_at is not null
  and private.chatdun_arena_is_conversation_pair(conversation_id, host_id, viewer_id)
);

grant select, insert, update on public.chatdun_arena_live_rooms to authenticated;
grant execute on function private.chatdun_arena_is_conversation_pair(uuid,uuid,uuid) to authenticated;

drop policy if exists "CHATDUN Arena private live room receive signals" on realtime.messages;
create policy "CHATDUN Arena private live room receive signals"
on realtime.messages for select to authenticated
using (
  realtime.messages.extension in ('broadcast','presence')
  and exists (
    select 1 from public.chatdun_arena_live_rooms r
    where ('arena-live:' || r.id::text) = (select realtime.topic())
      and (r.host_id = (select auth.uid()) or r.viewer_id = (select auth.uid()))
      and r.status = 'live' and r.expires_at > now()
      and private.chatdun_arena_is_conversation_pair(r.conversation_id,r.host_id,r.viewer_id)
  )
);

drop policy if exists "CHATDUN Arena private live room send signals" on realtime.messages;
create policy "CHATDUN Arena private live room send signals"
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension in ('broadcast','presence')
  and exists (
    select 1 from public.chatdun_arena_live_rooms r
    where ('arena-live:' || r.id::text) = (select realtime.topic())
      and (r.host_id = (select auth.uid()) or r.viewer_id = (select auth.uid()))
      and r.status = 'live' and r.expires_at > now()
      and private.chatdun_arena_is_conversation_pair(r.conversation_id,r.host_id,r.viewer_id)
  )
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chatdun_arena_live_rooms'
  ) then
    execute 'alter publication supabase_realtime add table public.chatdun_arena_live_rooms';
  end if;
end
$$;

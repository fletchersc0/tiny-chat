-- === Supabase Tiny Chat: Schema & Policies ===
create extension if not exists "pgcrypto";

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  room text not null check (length(room) between 1 and 64),
  user_name text not null check (length(user_name) between 1 and 40),
  body text not null check (length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists messages_room_created_idx on public.messages (room, created_at);
create index if not exists messages_created_idx on public.messages (created_at desc);

alter table public.messages enable row level security;

drop policy if exists "read messages" on public.messages;
create policy "read messages" on public.messages for select using (true);

drop policy if exists "post messages (1/s throttle)" on public.messages;
create policy "post messages (1/s throttle)" on public.messages
  for insert
  with check (
    not exists (
      select 1 from public.messages m
      where m.room = messages.room
        and m.user_name = messages.user_name
        and m.created_at > now() - interval '1 second'
    )
  );

alter publication supabase_realtime add table public.messages;
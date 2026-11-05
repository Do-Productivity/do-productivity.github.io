-- Usage tracker for My To Do List.
-- Paste the whole thing into Supabase → SQL Editor → Run. One time only.
-- Safe to run again later: every statement is write-once or replace-in-place.
--
-- What it records: a random id per device, a first-seen, a last-seen, and
-- the account id if that device happens to be signed in (so the tracker can
-- tell your own phone and Mac apart from everybody else's). No names, no
-- emails, no task text — nothing that says who anyone is or what they wrote.

-- ── 1. Count everyone who opens the app, account or not ──────────────

create table if not exists public.pings (
  device_id  uuid        primary key,
  user_id    uuid,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  hits       integer     not null default 1
);
alter table public.pings add column if not exists user_id uuid;

alter table public.pings enable row level security;
-- Deliberately no policies: nothing can read or write this table directly.
-- Only the two functions below touch it, and they run as its owner.

create or replace function public.record_visit(device uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.pings (device_id, user_id) values (device, auth.uid())
  on conflict (device_id) do update
    set last_seen = now(),
        hits      = pings.hits + 1,
        user_id   = coalesce(auth.uid(), pings.user_id);
$$;

revoke all on function public.record_visit(uuid) from public;
grant execute on function public.record_visit(uuid) to anon, authenticated;

-- ── 2. Totals for the tracker page ───────────────────────────────────
-- Returns counts and timestamps. Never a row of anybody's tasks.

create or replace function public.app_stats()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'generated', now(),
    'me',        auth.uid(),
    'people', (
      select coalesce(json_agg(json_build_object(
        'id', u.id, 'joined', u.created_at, 'last_sync', d.updated_at
      ) order by u.created_at), '[]'::json)
      from auth.users u
      left join public.documents d on d.user_id = u.id
    ),
    'devices', (
      select coalesce(json_agg(json_build_object(
        'first', first_seen,
        'last',  last_seen,
        'hits',  hits,
        'mine',  coalesce(user_id = auth.uid(), false)
      ) order by first_seen), '[]'::json)
      from public.pings
    )
  );
$$;

revoke all on function public.app_stats() from public;
grant execute on function public.app_stats() to authenticated;

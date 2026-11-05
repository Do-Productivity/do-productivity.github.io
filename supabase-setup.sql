-- My To Do List — everything the database needs.
-- Paste the whole thing into Supabase → SQL Editor → Run.
-- Safe to run again later: every statement is create-if-absent or
-- replace-in-place, and it never touches anybody's tasks.
--
-- Part 1 gives the usage tracker something to count.
-- Part 2 gives every account its own Apple Calendar feed, so the calendar
--   alerts stop depending on a GitHub token that only Ahmed has.

-- ═══ PART 1 · usage tracker ══════════════════════════════════════════
-- Records a random id per device, a first-seen, a last-seen, and the
-- account id when that device happens to be signed in (so the tracker can
-- tell your own phone and Mac from everybody else's). No names, no
-- emails, no task text.

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
-- Only the functions below touch it, and they run as its owner.

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

-- Supabase grants EXECUTE on new public functions to anon and authenticated
-- by default, and revoking from PUBLIC does not remove those named grants —
-- so anon has to be revoked explicitly or anyone holding the publishable key
-- can read the account list.
revoke all on function public.app_stats() from public, anon;
grant execute on function public.app_stats() to authenticated;

-- ═══ PART 2 · a calendar feed per account ════════════════════════════
-- The app already knows how to render its reminders as an .ics calendar —
-- that code is proven, alarms and all — so it uploads the finished text
-- with every sync and this just hands it back. Nothing is re-derived in
-- SQL, so the feed can never drift from what the app would produce.

alter table public.documents add column if not exists ics text;
alter table public.documents
  add column if not exists feed_token uuid not null default gen_random_uuid();

create unique index if not exists documents_feed_token_key
  on public.documents (feed_token);

-- PostgREST picks the response format from the request's Accept header, and
-- a domain named after a media type is how it is taught a new one. A plain
-- "text/calendar" domain only answers clients that ask for a calendar by
-- name; "*/*" is the catch-all, and the function sets the real Content-Type
-- itself, so every client gets a calendar no matter what it asks for.
do $$ begin
  create domain "*/*" as text;
exception when duplicate_object then null;
end $$;

drop function if exists public.feed(uuid);

create or replace function public.feed(t uuid)
returns "*/*"
language plpgsql
security definer
stable
set search_path = public
as $$
declare body text;
begin
  perform set_config('response.headers',
    '[{"Content-Type": "text/calendar; charset=utf-8"}]', true);
  -- Always one row: an account that has never synced gets a valid but
  -- empty calendar rather than an error the phone would keep retrying.
  select coalesce(
    (select d.ics from public.documents d where d.feed_token = t and d.ics is not null),
    'BEGIN:VCALENDAR' || chr(13) || chr(10) ||
    'VERSION:2.0'     || chr(13) || chr(10) ||
    'PRODID:-//dia-todo//EN' || chr(13) || chr(10) ||
    'X-WR-CALNAME:My To Do List' || chr(13) || chr(10) ||
    'END:VCALENDAR'   || chr(13) || chr(10)
  ) into body;
  return body;
end;
$$;

-- Readable by anyone holding the token, which is the whole point of a
-- subscribable feed URL — and the token is the only way in.
revoke all on function public.feed(uuid) from public;
grant execute on function public.feed(uuid) to anon, authenticated;

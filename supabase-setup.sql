-- My To Do List — everything the database needs.
-- Paste the whole thing into Supabase → SQL Editor → Run.
-- Safe to run again later: every statement is create-if-absent or
-- replace-in-place, and it never touches anybody's tasks.
--
-- Part 1 removes the usage tracker, and the figures it had gathered.
-- Part 2 gives every account its own Apple Calendar feed, so the calendar
--   alerts stop depending on a GitHub token that only Ahmed has.
-- Part 3 lets a person delete their own account from inside the app.

-- ═══ PART 1 · the usage tracker is gone ═════════════════════════════
-- The app used to send a random id per device so its owner could count
-- opens, and an owner-only function listed every account's email beside
-- its devices. The app no longer sends that id, and the owner no longer
-- keeps any of it. These lines remove the functions and DELETE THE DATA
-- already gathered. That cannot be undone, which is the intention.
--
-- A build of the app from before this change still calls record_visit. It
-- gets "not found", which it has always treated as "try again later".

drop function if exists public.app_stats();
drop function if exists public.record_visit(uuid);
drop table if exists public.pings;
drop table if exists public.app_owners;

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

-- ═══ PART 3 · deleting an account ════════════════════════════════════
-- Called by the app as the person who is signed in. It removes that
-- person and nobody else: auth.uid() comes from their own session, and
-- there is no parameter to point it at anyone else.
--
-- The row in documents holds the synced lists, the calendar feed and its
-- address. It goes first, explicitly, rather than trusting the cascade
-- alone. Deleting the auth.users row then removes the email address, the
-- password hash and every session, so other devices are signed out the
-- next time their token is checked.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'delete_account needs a signed-in person'
      using errcode = '42501';
  end if;
  delete from public.documents where user_id = me;
  delete from auth.users where id = me;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- PostgREST caches the list of functions. Tell it to look again, so the
-- app does not get "not found" for the minute after this is run.
notify pgrst, 'reload schema';

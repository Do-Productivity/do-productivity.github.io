-- My To Do List — everything the database needs.
-- Paste the whole thing into Supabase → SQL Editor → Run.
-- Safe to run again later: every statement is create-if-absent or
-- replace-in-place, and it never touches anybody's tasks.
--
-- Part 1 removes the usage tracker, and the figures it had gathered.
-- Part 2 gives every account its own Apple Calendar feed, so the calendar
--   alerts stop depending on a GitHub token that only Ahmed has.
-- Part 3 lets a person delete their own account from inside the app.
-- Part 4 is private sync: no accounts, and nothing stored that can be read.
-- Part 5 is the founding members: 1,000 seats and invitation codes, with
--   no names and no email addresses.

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

-- ═══ PART 4 · private sync: nothing here can be read ═════════════════
-- No accounts. A device makes a random id and a random key, encrypts its
-- lists with the key, and stores the result under the id. The key never
-- comes here, so these tables hold text nobody can read, belonging to
-- nobody this database can name.
--
-- "auth" is a token derived from the key on the device. Only its SHA-256
-- is kept. It proves that a caller may replace or erase a copy; it cannot
-- be turned back into the key.
--
-- Row level security is on with no policies, so nothing reaches these
-- tables except the five functions below.

create table if not exists public.vaults (
  id         uuid primary key,
  auth_hash  text        not null,
  blob       text        not null,
  updated_at timestamptz not null default now()
);
alter table public.vaults enable row level security;

-- A second device joins with a one-time code. The key waits here wrapped
-- by that code, for ten minutes, and is deleted the first time it is read.
create table if not exists public.pairings (
  id         text primary key,
  blob       text        not null,
  expires_at timestamptz not null
);
alter table public.pairings enable row level security;

create or replace function public.vault_put(v uuid, auth text, body text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  h     text := encode(sha256(convert_to(auth, 'utf8')), 'hex');
  held  text;
  stamp timestamptz := clock_timestamp();
begin
  if auth is null or length(auth) <> 64 or body is null or length(body) > 4000000 then
    raise exception 'vault_put: bad request' using errcode = '22023';
  end if;
  select auth_hash into held from public.vaults where id = v for update;
  if held is null then
    insert into public.vaults (id, auth_hash, blob, updated_at) values (v, h, body, stamp);
  elsif held = h then
    update public.vaults set blob = body, updated_at = stamp where id = v;
  else
    raise exception 'vault_put: this key does not match the copy' using errcode = '42501';
  end if;
  return stamp;
end;
$$;

create or replace function public.vault_get(v uuid, auth text, since timestamptz default null)
returns json
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  h   text := encode(sha256(convert_to(coalesce(auth, ''), 'utf8')), 'hex');
  rec public.vaults%rowtype;
begin
  select * into rec from public.vaults where id = v;
  if not found then
    return json_build_object('found', false);
  end if;
  if rec.auth_hash <> h then
    raise exception 'vault_get: this key does not match the copy' using errcode = '42501';
  end if;
  if since is not null and rec.updated_at <= since then
    return json_build_object('found', true, 'changed', false, 'at', rec.updated_at);
  end if;
  return json_build_object('found', true, 'changed', true, 'at', rec.updated_at, 'blob', rec.blob);
end;
$$;

create or replace function public.vault_delete(v uuid, auth text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  h    text := encode(sha256(convert_to(coalesce(auth, ''), 'utf8')), 'hex');
  held text;
begin
  select auth_hash into held from public.vaults where id = v;
  if held is null then
    return false;
  end if;
  if held <> h then
    raise exception 'vault_delete: this key does not match the copy' using errcode = '42501';
  end if;
  delete from public.vaults where id = v;
  return true;
end;
$$;

create or replace function public.pair_put(p text, body text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p is null or p !~ '^[0-9a-f]{32}$' or body is null or length(body) > 4000 then
    raise exception 'pair_put: bad request' using errcode = '22023';
  end if;
  delete from public.pairings where expires_at < now();
  insert into public.pairings (id, blob, expires_at)
  values (p, body, now() + interval '10 minutes')
  on conflict (id) do update set blob = excluded.blob, expires_at = excluded.expires_at;
end;
$$;

create or replace function public.pair_take(p text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare body text;
begin
  delete from public.pairings where expires_at < now();
  delete from public.pairings where id = p returning blob into body;
  return body;
end;
$$;

revoke all on function public.vault_put(uuid, text, text) from public;
revoke all on function public.vault_get(uuid, text, timestamptz) from public;
revoke all on function public.vault_delete(uuid, text) from public;
revoke all on function public.pair_put(text, text) from public;
revoke all on function public.pair_take(text) from public;
grant execute on function public.vault_put(uuid, text, text) to anon, authenticated;
grant execute on function public.vault_get(uuid, text, timestamptz) to anon, authenticated;
grant execute on function public.vault_delete(uuid, text) to anon, authenticated;
grant execute on function public.pair_put(text, text) to anon, authenticated;
grant execute on function public.pair_take(text) to anon, authenticated;


-- ═══ PART 5 · founding members and invitations ══════════════════════
-- The first 100 people get a founding seat. A seat is a number, a code to
-- give to friends, and a count of how often that code was used. There is no
-- name, no email address and no device identifier anywhere in it.
--
-- What proves a seat is yours is a key made on your device. Only its
-- SHA-256 hash is stored here, so reading this table does not let anyone
-- take a seat over. The invitation code is the public half: it is meant to
-- be passed around.
--
-- Free-for-life and the invited discount are both delivered as Apple offer
-- codes, because the App Store does not allow an app to unlock itself with
-- its own codes. Those cannot exist until the app is approved, so the two
-- places that hold them (founder_gifts and member_settings) start empty.
-- See "When the app is on the App Store" at the end of this part.

create table if not exists public.founders (
  no         integer primary key,              -- the seat number, 1 to 100
  key_hash   text not null unique,             -- sha256 of the member's key
  invite     text not null unique,             -- the code they give away
  uses       integer not null default 0,       -- how many people used it
  created_at timestamptz not null default now(),
  seen_on    date not null default current_date,  -- the day the app last asked about this seat
  gift       text                              -- the Apple code given to this member
);

create table if not exists public.invited (
  token_hash text primary key,                 -- sha256 of a random token on the invited device
  founder_no integer references public.founders(no) on delete set null,  -- an invitation outlives the seat it came from
  created_at timestamptz not null default now()
);

-- Apple one-time offer codes for a free lifetime purchase, loaded by the
-- owner once they can be generated. One is handed to each founding member.
create table if not exists public.founder_gifts (
  code  text primary key,
  taken boolean not null default false
);

-- One row of settings.
create table if not exists public.member_settings (
  id              boolean primary key default true check (id),
  seats           integer not null default 100,
  open            boolean not null default true,  -- false closes new seats without touching existing ones
  redeem_url      text,   -- Apple's redemption address, ending in "code="
  friend_lifetime text,   -- no longer used: the lifetime plan is not for sale
  friend_monthly  text,   -- Apple custom code: the monthly plan at 25% off
  friend_yearly   text    -- Apple custom code: the yearly plan at 25% off
);
insert into public.member_settings (id) values (true) on conflict (id) do nothing;
-- for a database set up before the plans became monthly and yearly, and
-- before the seats became 100
alter table public.member_settings add column if not exists friend_yearly text;
alter table public.member_settings alter column seats set default 100;
update public.member_settings set seats = 100 where seats = 1000;
-- An invitation outlives the seat it came from: in a database made before
-- this, giving up a seat also deleted the invitations it had handed out.
alter table public.invited alter column founder_no drop not null;
alter table public.invited drop constraint if exists invited_founder_no_fkey;
alter table public.invited add constraint invited_founder_no_fkey
  foreign key (founder_no) references public.founders(no) on delete set null;

-- Nobody reads or writes these tables directly: no policies, so only the
-- functions below can touch them.
alter table public.founders        enable row level security;
alter table public.invited         enable row level security;
alter table public.founder_gifts   enable row level security;
alter table public.member_settings enable row level security;

-- How many seats there are and how many are taken. Public: the landing
-- page shows it.
create or replace function public.founder_seats()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'seats', s.seats,
    'taken', (select count(*) from public.founders),
    'open',  s.open)
  from public.member_settings s;
$$;

-- Take a seat. k is the sha256 (64 hex characters) of a key the device
-- made. Asking again with the same k returns the same seat.
create or replace function public.founder_claim(k text)
returns json language plpgsql security definer set search_path = public as $$
declare
  f public.founders%rowtype;
  s public.member_settings%rowtype;
  code text;
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  tries integer := 0;
begin
  if k is null or k !~ '^[0-9a-f]{64}$' then
    return json_build_object('ok', false, 'reason', 'bad');
  end if;
  select * into f from public.founders where key_hash = k;
  if found then
    return json_build_object('ok', true, 'no', f.no, 'invite', f.invite, 'uses', f.uses);
  end if;

  -- one seat at a time, so two people can never be given the same number
  perform pg_advisory_xact_lock(7001000);
  select * into s from public.member_settings where id;
  if not s.open then
    return json_build_object('ok', false, 'reason', 'closed');
  end if;
  if (select count(*) from public.founders) >= s.seats then
    return json_build_object('ok', false, 'reason', 'full');
  end if;
  -- A brake, not a lock: with no accounts there is nothing to stop one
  -- person asking a thousand times, so seats go at most 120 an hour and a
  -- run on them is visible long before they are gone.
  if (select count(*) from public.founders where created_at > now() - interval '1 hour') >= 120 then
    return json_build_object('ok', false, 'reason', 'busy');
  end if;

  loop
    select string_agg(substr(abc, 1 + floor(random() * 32)::int, 1), '')
      into code from generate_series(1, 8);
    exit when not exists (select 1 from public.founders where invite = code);
    tries := tries + 1;
    if tries > 20 then return json_build_object('ok', false, 'reason', 'busy'); end if;
  end loop;

  -- the lowest free number, so a seat that was given back is used again
  insert into public.founders (no, key_hash, invite)
  values ((select min(n) from generate_series(1, s.seats) n
            where not exists (select 1 from public.founders where no = n)), k, code)
  returning * into f;
  return json_build_object('ok', true, 'no', f.no, 'invite', f.invite, 'uses', 0);
end;
$$;

-- What a founding member's app asks from time to time: the number, the
-- code, how many used it, and the Apple code once there is one.
create or replace function public.founder_status(k text)
returns json language plpgsql security definer set search_path = public as $$
declare
  f public.founders%rowtype;
  s public.member_settings%rowtype;
  g text;
begin
  if k is null or k !~ '^[0-9a-f]{64}$' then
    return json_build_object('found', false);
  end if;
  select * into f from public.founders where key_hash = k;
  if not found then
    return json_build_object('found', false);
  end if;
  if f.seen_on <> current_date then
    update public.founders set seen_on = current_date where no = f.no;
  end if;
  select * into s from public.member_settings where id;
  if f.gift is null and s.redeem_url is not null then
    update public.founder_gifts set taken = true
     where code = (select code from public.founder_gifts where not taken
                   order by code limit 1 for update skip locked)
    returning code into g;
    if g is not null then
      update public.founders set gift = g where no = f.no;
      f.gift := g;
    end if;
  end if;
  return json_build_object(
    'found', true, 'no', f.no, 'invite', f.invite, 'uses', f.uses,
    'gift', case when f.gift is not null and s.redeem_url is not null
                 then s.redeem_url || f.gift end);
end;
$$;

-- Use an invitation. c is the code as typed, t is the sha256 of a random
-- token the invited device made, so the same device counts once.
create or replace function public.invite_use(c text, t text)
returns json language plpgsql security definer set search_path = public as $$
declare
  f public.founders%rowtype;
  code text := upper(regexp_replace(coalesce(c, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if t is null or t !~ '^[0-9a-f]{64}$' or length(code) <> 8 then
    return json_build_object('ok', false, 'reason', 'unknown');
  end if;
  if exists (select 1 from public.invited where token_hash = t) then
    return json_build_object('ok', true);
  end if;
  select * into f from public.founders where invite = code;
  if not found then
    return json_build_object('ok', false, 'reason', 'unknown');
  end if;
  if (select count(*) from public.invited where created_at > now() - interval '1 hour') >= 600 then
    return json_build_object('ok', false, 'reason', 'busy');
  end if;
  insert into public.invited (token_hash, founder_no) values (t, f.no);
  update public.founders set uses = uses + 1 where no = f.no;
  return json_build_object('ok', true);
end;
$$;

-- What an invited person's app asks: is the invitation on record, and are
-- the discount codes ready yet.
create or replace function public.invite_status(t text)
returns json language plpgsql security definer set search_path = public as $$
declare
  s public.member_settings%rowtype;
begin
  if t is null or not exists (select 1 from public.invited where token_hash = t) then
    return json_build_object('found', false);
  end if;
  select * into s from public.member_settings where id;
  return json_build_object(
    'found', true,
    'yearly',   case when s.redeem_url is not null and s.friend_yearly is not null
                     then s.redeem_url || s.friend_yearly end,
    'monthly',  case when s.redeem_url is not null and s.friend_monthly is not null
                     then s.redeem_url || s.friend_monthly end);
end;
$$;

-- Give a seat back, from inside the app. The row is deleted; the number
-- becomes free for someone else.
create or replace function public.founder_leave(k text)
returns boolean language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.founders where key_hash = k returning no into n;
  return n is not null;
end;
$$;

-- Forget that this device was invited.
create or replace function public.invite_forget(t text)
returns boolean language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from public.invited where token_hash = t returning founder_no into n;
  if not found then return false; end if;
  update public.founders set uses = greatest(uses - 1, 0) where no = n;
  return true;
end;
$$;

revoke all on function public.founder_seats() from public;
revoke all on function public.founder_claim(text) from public;
revoke all on function public.founder_status(text) from public;
revoke all on function public.invite_use(text, text) from public;
revoke all on function public.invite_status(text) from public;
revoke all on function public.founder_leave(text) from public;
revoke all on function public.invite_forget(text) from public;
grant execute on function public.founder_seats() to anon, authenticated;
grant execute on function public.founder_claim(text) to anon, authenticated;
grant execute on function public.founder_status(text) to anon, authenticated;
grant execute on function public.invite_use(text, text) to anon, authenticated;
grant execute on function public.invite_status(text) to anon, authenticated;
grant execute on function public.founder_leave(text) to anon, authenticated;
grant execute on function public.invite_forget(text) to anon, authenticated;

-- When the app is on the App Store (not before: Apple only makes codes for
-- an approved app), run these three by hand, with your own values:
--
--   1. The redemption address, with your app's Apple ID in place of 0000000000:
--        update public.member_settings
--           set redeem_url = 'https://apps.apple.com/redeem?ctx=offercodes&id=0000000000&code=';
--   2. The free codes for the founding members: one-time-use codes for the
--      "Founding member" lifetime product, from App Store Connect, one per
--      line. Apple makes them 500 at a time; load only as many as there are
--      seats:
--        insert into public.founder_gifts (code) values ('CODE1'), ('CODE2');
--   3. The two custom codes for invited people (25% off):
--        update public.member_settings
--           set friend_yearly = 'YOURCODE', friend_monthly = 'YOURCODE';
--
-- To see how the seats are going:
--        select no, uses, created_at, seen_on, gift is not null as has_code
--          from public.founders order by no;
-- To close the seats early:   update public.member_settings set open = false;
-- To give back seats nobody has opened the app on for 90 days:
--        delete from public.founders where seen_on < current_date - 90 and gift is null;

notify pgrst, 'reload schema';

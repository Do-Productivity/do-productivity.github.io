-- Do. — founding members (Part 5 of supabase-setup.sql).
-- Paste all of this into Supabase → SQL Editor → Run. Safe to run again.

-- ═══ PART 5 · founding members and invitations ══════════════════════
-- The first 1,000 people get a founding seat. A seat is a number, a code to
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
  no         integer primary key,              -- the seat number, 1 to 1000
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
  seats           integer not null default 1000,
  open            boolean not null default true,  -- false closes new seats without touching existing ones
  redeem_url      text,   -- Apple's redemption address, ending in "code="
  friend_lifetime text,   -- Apple custom code: the lifetime plan at 25% off
  friend_monthly  text    -- Apple custom code: the monthly plan at 25% off
);
insert into public.member_settings (id) values (true) on conflict (id) do nothing;

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
    'lifetime', case when s.redeem_url is not null and s.friend_lifetime is not null
                     then s.redeem_url || s.friend_lifetime end,
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
--   2. The free lifetime codes for the founding members (one-time-use codes
--      from App Store Connect, one per line):
--        insert into public.founder_gifts (code) values ('CODE1'), ('CODE2');
--   3. The two custom codes for invited people (25% off):
--        update public.member_settings
--           set friend_lifetime = 'YOURCODE', friend_monthly = 'YOURCODE';
--
-- To see how the seats are going:
--        select no, uses, created_at, seen_on, gift is not null as has_code
--          from public.founders order by no;
-- To close the seats early:   update public.member_settings set open = false;
-- To give back seats nobody has opened the app on for 90 days:
--        delete from public.founders where seen_on < current_date - 90 and gift is null;

notify pgrst, 'reload schema';

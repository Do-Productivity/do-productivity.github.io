-- Do. — referrals (Part 6 of supabase-setup.sql), for version 1.1.
-- Paste all of this into Supabase → SQL Editor → Run. Safe to run again.
-- Needs Part 5 (founding members) first: it reads member_settings.redeem_url.

-- ═══ PART 6 · give a month, get a month ═════════════════════════════
-- See REFERRALS-PLAN.md. In short:
--   · everyone has one referral code;
--   · a friend enters it and subscribes: the friend gets a free month;
--   · when the friend's payment is 14 days old and not refunded, the
--     referrer gets a free month, and every 10 such friends a free year.
--
-- Every reward is an Apple offer code, redeemed in the App Store: Apple does
-- not allow an app to unlock itself with codes of its own (guideline 3.1.1).
--
-- What proves a purchase is Apple's own signed transaction. The app cannot
-- record a conversion; only the server function `referral-convert` can,
-- after it has checked Apple's signature. That function runs with the
-- service role, which is the only role allowed to call referral_convert and
-- referral_refund below.
--
-- What is kept, and nothing else (the privacy policy says the same):
--   referrers             sha256 of a key made on the device, the code
--   referred              sha256 of a random token on the friend's device,
--                         which code they entered, when
--   referral_conversions  Apple's original transaction id (a number, not a
--                         name), the product, when it was paid, whether it
--                         was refunded, whether it was a TestFlight purchase
--   referral_rewards      which of the above earned which reward, and the
--                         Apple code given for it
-- No name, no email address, no device identifier, no link to anyone's lists.

create table if not exists public.referrers (
  key_hash   text primary key,                    -- sha256 of the referrer's key
  code       text not null unique,                -- the code they share
  created_at timestamptz not null default now(),
  seen_on    date not null default current_date   -- the day the app last asked
);

create table if not exists public.referred (
  token_hash text primary key,                    -- sha256 of a token on the friend's device
  code       text not null,                       -- the referrer's code they entered
  created_at timestamptz not null default now()
);

create table if not exists public.referral_conversions (
  original_tx text primary key,                   -- Apple's original transaction id
  token_hash  text not null unique,               -- one conversion per referred friend
  code        text not null,                      -- the referrer credited
  product     text not null,
  sandbox     boolean not null default false,     -- a TestFlight or Xcode purchase: no real reward
  paid_at     timestamptz not null,
  refunded    boolean not null default false,
  counted     boolean not null default false,     -- 14 days passed unrefunded; the referrer was credited
  created_at  timestamptz not null default now()
);

create table if not exists public.referral_rewards (
  id         bigserial primary key,
  holder     text not null,                       -- referrers.key_hash, or referred.token_hash
  who        text not null check (who in ('referrer', 'friend')),
  kind       text not null check (kind in ('month', 'year')),
  reason     text not null,                       -- the original_tx it is for, or 'ten:<n>'
  plan       text not null default 'monthly' check (plan in ('monthly', 'yearly')),
  apple_code text,                                -- null until a code is free in the pool
  test_only  boolean not null default false,      -- earned in TestFlight: shown, never given a real code
  created_at timestamptz not null default now(),
  unique (holder, reason)
);

-- Apple one-time offer codes, loaded by the owner in batches. One is handed
-- out per reward. month_monthly: Do. Monthly, 1 month free. month_yearly:
-- Do. Yearly, 1 month free. year_yearly: Do. Yearly, 1 year free.
create table if not exists public.referral_codes (
  code  text primary key,
  kind  text not null check (kind in ('month_monthly', 'month_yearly', 'year_yearly')),
  taken boolean not null default false
);

-- Nobody reads or writes these directly: no policies, only the functions.
alter table public.referrers            enable row level security;
alter table public.referred             enable row level security;
alter table public.referral_conversions enable row level security;
alter table public.referral_rewards     enable row level security;
alter table public.referral_codes       enable row level security;

-- A reward waiting for an Apple code gets one, if the pool has one.
-- Codes are taken one at a time and never handed out twice.
create or replace function public.referral_fill(r_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare
  r public.referral_rewards%rowtype;
  want text;
  got text;
begin
  select * into r from public.referral_rewards where id = r_id for update;
  if not found or r.apple_code is not null or r.test_only then return r.apple_code; end if;
  want := case when r.kind = 'year' then 'year_yearly'
               when r.plan = 'yearly' then 'month_yearly'
               else 'month_monthly' end;
  select code into got from public.referral_codes
   where kind = want and not taken
   order by code limit 1 for update skip locked;
  if got is null then return null; end if;
  update public.referral_codes set taken = true where code = got;
  update public.referral_rewards set apple_code = got where id = r_id;
  return got;
end;
$$;

-- The referrer's side, asked when the Sync sheet is open. k is the sha256
-- (64 hex) of a key the device made; p is the plan they are on, so a free
-- month is for the plan they have. Makes the code the first time; credits
-- friends whose 14 days have passed; hands out the Apple codes.
create or replace function public.referral_mine(k text, p text default 'monthly')
returns json language plpgsql security definer set search_path = public as $$
declare
  me public.referrers%rowtype;
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
  tries integer := 0;
  plan text := case when p = 'yearly' then 'yearly' else 'monthly' end;
  n integer;
  r record;
begin
  if k is null or k !~ '^[0-9a-f]{64}$' then
    return json_build_object('ok', false, 'reason', 'bad');
  end if;
  select * into me from public.referrers where key_hash = k;
  if not found then
    -- a brake, as for founding seats: codes are made at most 600 an hour
    if (select count(*) from public.referrers where created_at > now() - interval '1 hour') >= 600 then
      return json_build_object('ok', false, 'reason', 'busy');
    end if;
    loop
      select string_agg(substr(abc, 1 + floor(random() * 32)::int, 1), '')
        into c from generate_series(1, 8);
      exit when not exists (select 1 from public.referrers where code = c)
            and not exists (select 1 from public.founders where invite = c);
      tries := tries + 1;
      if tries > 20 then return json_build_object('ok', false, 'reason', 'busy'); end if;
    end loop;
    insert into public.referrers (key_hash, code) values (k, c) returning * into me;
  elsif me.seen_on < current_date then
    update public.referrers set seen_on = current_date where key_hash = k;
  end if;

  -- friends whose first payment is 14 days old and was not refunded
  for r in
    select * from public.referral_conversions
     where code = me.code and not counted and not refunded
       and paid_at <= now() - interval '14 days'
     for update
  loop
    update public.referral_conversions set counted = true where original_tx = r.original_tx;
    insert into public.referral_rewards (holder, who, kind, reason, plan, test_only)
    values (k, 'referrer', 'month', r.original_tx, plan, r.sandbox)
    on conflict (holder, reason) do nothing;
  end loop;

  -- every 10 counted friends, a free year (TestFlight friends count only
  -- towards TestFlight years)
  select count(*) into n from public.referral_conversions
   where code = me.code and counted and not refunded and not sandbox;
  for i in 1 .. (n / 10) loop
    insert into public.referral_rewards (holder, who, kind, reason, plan)
    values (k, 'referrer', 'year', 'ten:' || i, 'yearly')
    on conflict (holder, reason) do nothing;
  end loop;

  for r in select id from public.referral_rewards where holder = k and apple_code is null and not test_only loop
    perform public.referral_fill(r.id);
  end loop;

  return json_build_object(
    'ok', true,
    'code', me.code,
    'counted', (select count(*) from public.referral_conversions
                 where code = me.code and counted and not refunded),
    'waiting', coalesce((select json_agg(extract(epoch from paid_at + interval '14 days')::bigint * 1000 order by paid_at)
                  from public.referral_conversions
                 where code = me.code and not counted and not refunded), '[]'::json),
    'rewards', coalesce((select json_agg(json_build_object('kind', kind, 'code', apple_code, 'test', test_only) order by id)
                  from public.referral_rewards where holder = k), '[]'::json),
    'redeem', (select redeem_url from public.member_settings where id)
  );
end;
$$;

-- A friend enters a code. t is the sha256 of a random token their device
-- made; k, if they have a referral code of their own, is its key's sha256,
-- so a code cannot be used by the person it belongs to.
create or replace function public.referral_use(c text, t text, k text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  owner text;
  prev text;
begin
  if c is null or c !~ '^[A-Z2-9]{8}$' or t is null or t !~ '^[0-9a-f]{64}$' then
    return json_build_object('ok', false, 'reason', 'bad');
  end if;
  select key_hash into owner from public.referrers where code = c;
  if owner is null then return json_build_object('ok', false, 'reason', 'unknown'); end if;
  if k is not null and owner = k then return json_build_object('ok', false, 'reason', 'own'); end if;
  if exists (select 1 from public.referral_conversions where token_hash = t) then
    return json_build_object('ok', false, 'reason', 'done');
  end if;
  select code into prev from public.referred where token_hash = t;
  if prev is null then
    insert into public.referred (token_hash, code) values (t, c);
  elsif prev <> c then
    -- not yet subscribed: the latest code entered is the one that counts
    update public.referred set code = c, created_at = now() where token_hash = t;
  end if;
  return json_build_object('ok', true);
end;
$$;

-- The friend's side: their free month, once their purchase has been seen.
create or replace function public.referral_friend(t text)
returns json language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if t is null or t !~ '^[0-9a-f]{64}$' then return json_build_object('found', false); end if;
  if not exists (select 1 from public.referred where token_hash = t) then
    return json_build_object('found', false);
  end if;
  for r in select id from public.referral_rewards where holder = t and apple_code is null and not test_only loop
    perform public.referral_fill(r.id);
  end loop;
  return json_build_object(
    'found', true,
    'code', (select code from public.referred where token_hash = t),
    'converted', exists (select 1 from public.referral_conversions where token_hash = t),
    'rewards', coalesce((select json_agg(json_build_object('kind', kind, 'code', apple_code, 'test', test_only) order by id)
                  from public.referral_rewards where holder = t), '[]'::json),
    'redeem', (select redeem_url from public.member_settings where id));
end;
$$;

-- Called only by the server function, after Apple's signature checked out.
create or replace function public.referral_convert(t text, otx text, product text, paid bigint, sandbox boolean)
returns json language plpgsql security definer set search_path = public as $$
declare
  c text;
  r_id bigint;
  plan text := case when product like '%.yearly' then 'yearly' else 'monthly' end;
begin
  if t is null or t !~ '^[0-9a-f]{64}$' or otx is null or otx !~ '^[0-9]{1,24}$' then
    return json_build_object('ok', false, 'reason', 'bad');
  end if;
  select code into c from public.referred where token_hash = t;
  if c is null then return json_build_object('ok', false, 'reason', 'not_referred'); end if;
  -- the same Apple subscription counts once, whichever device sends it
  if exists (select 1 from public.referral_conversions where original_tx = otx) then
    return json_build_object('ok', true, 'reason', 'seen');
  end if;
  if exists (select 1 from public.referral_conversions where token_hash = t) then
    return json_build_object('ok', true, 'reason', 'seen');
  end if;
  insert into public.referral_conversions (original_tx, token_hash, code, product, sandbox, paid_at)
  values (otx, t, c, product, sandbox, to_timestamp(paid / 1000.0));
  insert into public.referral_rewards (holder, who, kind, reason, plan, test_only)
  values (t, 'friend', 'month', otx, plan, sandbox)
  on conflict (holder, reason) do nothing
  returning id into r_id;
  if r_id is not null then perform public.referral_fill(r_id); end if;
  return json_build_object('ok', true);
end;
$$;

-- Called only by the server function that hears from Apple: a refund or a
-- revocation means that purchase never earns the referrer anything. A
-- reward already given stays given (Apple codes cannot be taken back).
create or replace function public.referral_refund(otx text)
returns json language plpgsql security definer set search_path = public as $$
begin
  update public.referral_conversions set refunded = true where original_tx = otx;
  return json_build_object('ok', true, 'found', found);
end;
$$;

-- Forget my referral code. Friends already credited stay credited; the
-- code stops working for anyone new.
create or replace function public.referral_forget(k text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if k is null or k !~ '^[0-9a-f]{64}$' then return json_build_object('ok', false); end if;
  delete from public.referral_rewards where holder = k;
  delete from public.referrers where key_hash = k;
  return json_build_object('ok', true);
end;
$$;

revoke all on function public.referral_fill(bigint) from public;
revoke all on function public.referral_mine(text, text) from public;
revoke all on function public.referral_use(text, text, text) from public;
revoke all on function public.referral_friend(text) from public;
revoke all on function public.referral_convert(text, text, text, bigint, boolean) from public;
revoke all on function public.referral_refund(text) from public;
revoke all on function public.referral_forget(text) from public;
grant execute on function public.referral_mine(text, text) to anon, authenticated;
grant execute on function public.referral_use(text, text, text) to anon, authenticated;
grant execute on function public.referral_friend(text) to anon, authenticated;
grant execute on function public.referral_forget(text) to anon, authenticated;
grant execute on function public.referral_convert(text, text, text, bigint, boolean) to service_role;
grant execute on function public.referral_refund(text) to service_role;
-- Supabase grants every new function to anon and authenticated by default,
-- separately from "public", so those grants are taken back by name. Without
-- this the app's public key could record a purchase and skip Apple's check.
revoke execute on function public.referral_fill(bigint) from anon, authenticated;
revoke execute on function public.referral_convert(text, text, text, bigint, boolean) from anon, authenticated;
revoke execute on function public.referral_refund(text) from anon, authenticated;

-- ═══ When the offer codes exist (after 1.0 is approved) ═════════════
-- Load each batch Apple gives you. Paste the codes, one per line, between
-- the $$ marks, and set the kind:
--
--   insert into public.referral_codes (code, kind)
--   select trim(x), 'month_monthly'
--     from regexp_split_to_table($$
--   PASTE CODES HERE
--   $$, '\s+') x where trim(x) <> ''
--   on conflict (code) do nothing;
--
-- How many are left of each:
--   select kind, count(*) filter (where not taken) as left, count(*) as loaded
--     from public.referral_codes group by kind;

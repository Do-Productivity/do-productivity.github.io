# Founding members: how it works

Written 12 November 2026, updated 13 November (100 seats; monthly and yearly plans). This covers what is stored, how the limit of 100
is kept, how invitations work, and the three small steps that are yours.

## 1. What a founding seat is

A seat is one row on the server. It holds:

| Stored | What it is |
|---|---|
| Seat number | 1 to 100 |
| Key fingerprint | A SHA-256 hash of a random key made on the member's device |
| Invitation code | 8 letters and numbers, meant to be shared |
| Uses | How many people used that invitation |
| Two dates | When the seat was taken, and the last day the app checked it |
| Apple code | Empty until the app is on the App Store |

There is no name, no email address, no device identifier and no link to
anyone's lists. An invited person's row holds a fingerprint of a random token
from their device, the seat number that invited them, and the time.

## 2. How the privacy holds

- **The key never leaves the device.** The device makes a random key and
  sends only its fingerprint. Reading the server does not let anyone take over
  a seat, because the fingerprint cannot be turned back into the key.
- **On iPhone the key is in the Keychain**, with the sync key.
- **Between a person's own devices it travels only inside the encrypted sync
  copy**, which the server cannot read. It is never put in the older kinds of
  sync.
- **Nobody is announced to the server by default.** The app asks about seats
  only when someone opens Sync, or already holds a seat or an invitation.
- **It can be undone from inside the app.** "Give up this seat" and "Forget
  this invitation" delete the row straight away.
- **The tables cannot be read from outside.** They have no access rules, so
  only the seven functions in the database script can touch them, and none of
  them lists seats.

## 3. How invitations work

1. A founding member's app shows their code, for example `N2UE-4XP6`, and a
   Share button that sends a link with the code in it.
2. The friend opens Sync, types the code (capitals do not matter) and taps
   Use this invitation. The link fills it in for them.
3. The server checks the code belongs to a real seat, records the invitation
   once for that device, and adds one to the member's count.
4. The member sees "3 people have joined with your invitation". They never
   see who.

## 4. How the limit of 100 is kept

**Never more than 100.** The server gives out seats one at a time behind a
lock, counts the rows first, and refuses when 100 exist. Two people asking
at the same instant cannot both get the last seat or the same number. The
app cannot override this: the count lives on the server.

**Numbers stay within 1 to 100.** A seat that is given up goes back into
the pool, and the next person gets the lowest free number.

**What "not fewer" can and cannot mean.** The server cannot make people
join, so the count reaches 100 only when 100 seats are taken. What it
does guarantee is that no seat is lost: none can be taken twice, and a seat
given up is offered again.

**The honest weak point.** With no accounts, the server cannot tell two
people from one person asking twice. It only slows this down, to 120 seats
an hour. Two things close the gap:

- Keeping the seats shut until launch (section 5), so nobody can collect
  them early.
- Apple. Free for life is delivered as an Apple code, and Apple allows one
  code per Apple Account. You load exactly 100 codes, so at most 100
  free copies can ever exist, one per Apple Account, whatever happens to the
  seats.

To see the seats at any time, in Supabase's SQL Editor:

```sql
select no, uses, created_at, seen_on, gift is not null as has_code
  from public.founders order by no;
```

To release seats that no device has opened for 90 days:

```sql
delete from public.founders where seen_on < current_date - 90 and gift is null;
```

## 5. Starting at the App Store launch, with you as No. 1

Three steps. The first two are for now.

**Step 1. Check you hold No. 1.** Open Do., tap Sync, and look for the card
"Founding member No. 1". The server shows one seat taken as of this evening.
If your app does not show No. 1, tell me before doing step 2.

**Step 2. Hold the other 999 until launch.** Run this one line in Supabase's
SQL Editor:

```sql
update public.member_settings set open = false;
```

From then on the app and the landing page say "Founding seats open the day
Do. arrives on the App Store", and nobody can take a seat. Your seat, your
badge and your invitation code keep working.

**Step 3. On launch day, open them.** Once the app is approved:

```sql
update public.member_settings set open = true;
```

That same day, also load the Apple codes. In App Store Connect, create a free
offer for the "Founding member" lifetime product and generate one-time-use
codes. Apple makes them 500 at a time; load only the first 100. Then:

```sql
update public.member_settings
   set redeem_url = 'https://apps.apple.com/redeem?ctx=offercodes&id=YOUR_APP_ID&code=';
insert into public.founder_gifts (code) values ('CODE1'), ('CODE2');  -- 100 of them
update public.member_settings
   set friend_yearly = 'YOURCODE', friend_monthly = 'YOURCODE';       -- the 25% codes
```

No app update is needed for any of this. Each founding member's app then
shows "Get Do. free for life in the App Store", and each invited person's app
shows the two discount buttons.

## 6. Three things to know about Apple's side

- **The plans are monthly and yearly, so "free for life" needs its own
  product.** A subscription cannot be given away for ever. The app keeps a
  third product, a lifetime purchase called "Founding member", that is never
  shown for sale. A founding member's Apple code redeems it at no charge, and
  from then on the app treats them as paid for good.

- **Apple's one-time codes expire within six months.** A member who has not
  redeemed by then needs a fresh code, which means generating a new batch and
  loading it the same way.
- **The 25% for invited people** is applied by Apple codes on the two
  subscriptions: the first year at 25% off on the yearly plan, and a set
  number of months at 25% off on the monthly plan. Apple does not offer a
  code that discounts a subscription for ever.
- **An app may not unlock itself with its own codes** (App Review guideline
  3.1.1). That is why the seat is a badge and a place in the queue, and the
  free copy itself comes from Apple.

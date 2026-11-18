# Referrals: plan for version 1.1

Decided 15 November 2026.

## The offer

- Everyone gets one referral code, founding member or not.
- A friend enters the code and subscribes (monthly or yearly): **the friend
  gets a free month** straight away.
- Once the friend's payment is **14 days old and not refunded**, **the
  referrer gets a free month**, and it counts towards their tally.
- **Every 10 counted referrals, the referrer gets a free year.**
- The founders' 25% discount is cancelled. Founders keep free for life.

## Why it is built this way

**The app cannot give itself free time.** Apple forbids an app unlocking its
own content with its own codes (guideline 3.1.1). Every reward is therefore an
Apple **offer code**, redeemed in the App Store, exactly like the founders'
free-for-life code. The app shows the code with a button that opens Apple's
redemption page.

**A referral must be a real purchase.** With no accounts, the only trustworthy
proof is Apple's own signed transaction. When a referred friend subscribes, the
app sends that signed transaction to our server, which checks Apple's
signature, the app, the product and that it was a real paid purchase, and that
the same purchase has not been counted before. Nothing else is trusted.

**Refunds.** A referrer's reward waits 14 days, and Apple's server
notifications tell us about refunds, so a subscribe-then-refund does not earn
anything.

## What the server keeps (privacy)

| Record | Holds |
|---|---|
| Referrer | fingerprint of a key made on the device, the referral code, counted referrals, rewards given |
| Referred friend | fingerprint of a random token, which code they used, the time |
| Conversion | Apple's original transaction id (a number, not a name), product, date paid, refunded or not |

No name, no email, no device identifier, no link to lists. The App Store
privacy label gains **Purchases – not linked to you** (agreed). The privacy
policy gets a paragraph saying exactly the table above.

## What gets built

1. **Database:** tables for referrers, referred friends, conversions and a pool
   of Apple codes per reward; functions to get your code, use a code, see your
   tally and your rewards.
2. **A small server function (Supabase Edge Function):** receives the signed
   transaction, verifies it against Apple's certificates, records the
   conversion; a second one receives Apple's server notifications (renewals,
   refunds).
3. **The app:** a "Refer a friend" card in Sync (your code, Share, your tally
   "3 of 10 to a free year", your rewards with Redeem buttons); a "Have a
   referral code?" box on the plans screen; after a purchase, it sends the
   signed transaction if the person used a code.
4. **Tests:** the database and server function against fake signed
   transactions; the app screens on every screen size.

## What you will need to do

1. **Supabase:** let me deploy server functions. You create a personal access
   token in the Supabase dashboard (Account → Access Tokens) and paste it into
   a terminal prompt I open; it is never written into the project.
2. **App Store Connect, after 1.0 is approved:**
   - set the **Production Server URL** for App Store Server Notifications to
     the function's address I give you (App Information, lower down);
   - create the offer codes, one-time-use, in batches of 500:
     - Do. Monthly, **1 month free**, for new and existing subscribers;
     - Do. Yearly, **1 month free**, for new and existing subscribers;
     - Do. Yearly, **1 year free**, for new and existing subscribers.
   Codes expire after at most six months, so a new batch goes in twice a year.
3. **Privacy label:** add **Purchases** (not linked, app functionality).

## Order

1. 1.0 approved and released (with build 1.0 (3)).
2. Founder codes loaded (unchanged plan, without the 25% codes).
3. Build referrals, test, then submit 1.1.

## Online (18 November 2026)

Database part, both server functions and REFERRAL_ALLOW_SANDBOX=1 deployed
with `scripts/deploy-referrals.sh`. Checked from outside with the public key:
the app gets a code; it cannot record a purchase, a refund or hand out a code
(permission denied, after taking back Supabase's default grants); the
function refuses an unsigned purchase; the listener refuses an unsigned
notice. Apple Root CA - G3 fingerprint checked against apple.com.

Still to do, after 1.0 is approved: the notifications URL and the offer codes
in App Store Connect (step 4 below); publish the web app with the 1.1 code
before 1.1 is released, so shared #ref links explain themselves.

## Built (18 November 2026)

| Part | Where | Tested by |
|---|---|---|
| Database: codes, a friend's code, the 14 days, refunds, the free year, the code pool | `supabase-part-6-referrals.sql` | `t_referral_sql.mjs` (35 checks, real Postgres via PGlite) |
| Server function: checks Apple's signature on the friend's purchase | `supabase/functions/referral-convert/` + `_shared/apple-core.js` | `t_referral_verify.mjs` (22 checks: forgeries, edits, other roots, expired, Family Sharing, free starts) |
| Server function: Apple's refund notices | `supabase/functions/apple-notifications/` | same verifier |
| App: Refer a friend card in Sync, Have a friend's code?, Redeem, Stop using my code | `index.html` | `t_referral_app.mjs` (37 checks, several mock iPhones) |
| iPhone: hands Apple's signed purchase to the app; the plans screen shows the friend's code | `StoreBridge.swift` | builds; the flow is covered by the app test |
| Privacy policy, support page, privacy label, app privacy file | `privacy/`, `support/`, `APP-STORE-LISTING.md`, `PrivacyInfo.xcprivacy` | read through |

TestFlight purchases are recorded as test-only: testers see the whole flow and
no real Apple code is spent (while `REFERRAL_ALLOW_SANDBOX=1` is set).

### To put it online

1. **Check Apple's root certificate.** `_shared/apple-core.js` pins Apple Root
   CA - G3 by its SHA-256. Before deploying, download AppleRootCA-G3.cer from
   apple.com/certificateauthority (with your OK) and compare the fingerprint.
2. **Database:** paste `supabase-part-6-referrals.sql` into Supabase → SQL
   Editor → Run.
3. **Functions** (needs your access token, typed into a terminal prompt):
   `supabase functions deploy referral-convert --no-verify-jwt` and
   `supabase functions deploy apple-notifications --no-verify-jwt`, then
   `supabase secrets set REFERRAL_ALLOW_SANDBOX=1` for the TestFlight period.
4. **App Store Connect** (after 1.0 is approved): the Production Server URL
   for notifications is
   `https://mxlbafuzdbnypexhgptw.supabase.co/functions/v1/apple-notifications`;
   create the offer codes and load them (instructions at the end of the SQL).
5. **Before 1.1 goes to App Review:** set `REFERRAL_ALLOW_SANDBOX` to 0 only
   if App Review should not see the flow; leaving it on is harmless, since
   test purchases never get real codes.

## Also in 1.1: dated tasks in Apple Calendar (agreed 15 November 2026)

- A switch, off by default: "Add my dated tasks to Apple Calendar". iPhone asks
  once for permission to change calendars.
- Do. writes only inside its own calendar called "Do." (iCloud when
  available, so it reaches the Mac and iPad). It never touches any other
  calendar; the Swift side enforces that.
- One entry per dated task, tagged with the task's id: moved, renamed or
  removed with the task; repeating tasks show their next time only.
- **One alert, not two:** the calendar entries carry no alarm. Do. rings
  from the phone as it does now.
- Do.'s own Calendar screen hides the "Do." calendar, so nothing appears twice.
- Turning the switch off deletes the "Do." calendar, and nothing else.
- The permission text changes from "only read, never changed" to say Do. adds
  dated tasks to its own Do. calendar and changes no other.
- Nothing passes through the server; the privacy label is unchanged.

**Status, 15 November 2026:** built on the `v1.1` branch and tested (34
checks with a stand-in for the phone; on the iPhone Duo simulator against the
real calendar store, the tasks appear in Apple's Calendar app). The privacy
page, support page, landing page and App Store notes say what it does; they go
live with 1.1. Pictures: `brand/calendar-preview/`.

## Also in 1.1: your iPhone's meetings on the web (agreed 16 November 2026)

Why: the web cannot read anybody's calendar, so Do. on the laptop only had a
calendar file imported on 12 November, which never updates. A meeting added
later (a Wednesday coffee) was on the phone and in Apple Calendar but not on
the web.

- A second switch in the phone's calendar settings: **Show my meetings on my
  other devices**. Off by default.
- When on, the phone adds its meetings for 2 days back and 8 weeks ahead to
  the private sync copy, which is sealed on the phone with the key only the
  person's devices hold. The server keeps a copy it cannot open, exactly as
  for the lists. Nothing goes into the GitHub mirror or any other sync.
- Only title, time, place, calendar name and colour travel. Notes, links,
  organiser and invitees stay on the phone. Cancelled and declined meetings,
  and calendars hidden in Do., are left out.
- The phone reads at most every 5 minutes while Do. is open, and uploads
  only when something changed. The web shows them in its Calendar and Today,
  labelled "Meetings from your iPhone". A phone never shows them (it has its
  own), so nothing appears twice.
- Off: the other devices delete their copy at their next sync. Stopping sync
  on a device deletes its copy too.
- Privacy: privacy policy, in-app "What leaves this device", support page,
  iOS permission text and SECURITY.md updated. The App Store privacy answer
  stays "Calendar: not collected", because it travels only end-to-end
  encrypted, like the lists.
- Tested: `t_meetshare` (26 checks, two devices through the mock server).

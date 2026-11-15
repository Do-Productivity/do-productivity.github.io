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

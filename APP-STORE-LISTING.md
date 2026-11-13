# App Store listing: everything to paste

Prepared 13 November 2026 for the renewed developer account (team
`6MCMG3FEW8`, Individual, Egypt). Texts are within Apple's length limits.
Where something is your decision, it says so.

## 1. The app record (App Store Connect → Apps → +)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `Do.` first. If Apple says it is taken: `Do. Lists & Calendar`, then `Do. To-Do, Notes & Plans` |
| Primary language | English (U.S.) |
| Bundle ID | `io.github.do-productivity.do` (appears in the list after the first upload or once registered) |
| SKU | `do-ios-1` |
| User access | Full access |

Devices: iPhone only for version 1.0. iPad can be added later; Apple does not
allow it to be removed once released.

## 2. Version 1.0 page

| Field | Limit | Text |
|---|---|---|
| Subtitle | 30 | `Lists that follow the fold` |
| Promotional text | 170 | `Closed, one list. Open, all of them. Tasks, notes, plans and your calendar in one calm place. No account, no sign-up, and your lists stay on your device.` |
| Keywords | 100 | `todo,tasks,list,planner,calendar,reminders,notes,widget,checklist,agenda,foldable,private,schedule` |
| Support URL | | `https://do-productivity.github.io/support/` |
| Marketing URL | | `https://do-productivity.github.io/` |
| Privacy Policy URL | | `https://do-productivity.github.io/privacy/` |
| Copyright | | `2026 Ahmed Hassaan` |
| Category | | Primary: Productivity. Secondary: none |
| Age rating | | Answer "None" to every question. Result: 4+ |

The promotional text can be changed at any time without a new review, so it is
the place for the founding-members line once the seats open:
`The first 100 founding members get Do. free for life. Take a seat in the app.`

### Description

```
Do. is a to-do list that follows your phone.

On iPhone Duo, closed shows one list at a time. Open it and your lists sit side by side, with room for your plans and your calendar. Turn it upright and every list is still on screen. Nothing to set up and nothing to drag into place. On any other iPhone it is a calm, quick list app.

YOUR DAY, IN ONE TIMELINE
The Today screen shows the tasks that have a time and the meetings in your calendar, in the order they happen. One tap hides the meetings when you only want the work.

TYPE IT THE WAY YOU SAY IT
Write "Call the bank tomorrow 3pm" and Do. takes the time out of the sentence and sets the reminder. It shows what it understood while you type.

BIG JOBS, STEP BY STEP
Some work is not one tick. Give it a start, a deadline and the steps in between.

YOUR CALENDAR, BESIDE YOUR TASKS
Do. reads the calendar on your iPhone so you can plan around it. It never changes it. Tap an empty hour to add a task at that time.

WIDGETS
What is next on your Lock Screen. Your week on your Home Screen.

PRIVATE BY DESIGN
Do. has no accounts. It never asks for your name or your email address.
- Your lists stay on your device unless you turn on sync.
- If you sync, your lists are encrypted on your device first. The key stays on your devices and is never sent to us.
- Adding a device takes a one-time code, your approval, and a number typed back.
- No advertising and no tracking.

PLANS
Everything works free for 14 days. After that, choose the monthly or the yearly plan. Both renew until you cancel. Whatever you choose, the lists you wrote stay yours to read and export.

Questions: https://do-productivity.github.io/support/
```

## 3. Pictures and video (ready, in `brand/app-store/`)

All pictures are real captures from Apple's simulators with invented tasks,
the clock at 9:41, and no transparency. There are two versions of each set;
upload one or the other, not both.

| Folder | What | Size | Count |
|---|---|---|---|
| `screenshots-captioned/iphone-6.9/` | With a headline (recommended) | 1320 × 2868 | 6 |
| `screenshots-captioned/iphone-duo-outer/` | With a headline | 1398 × 2034 | 6 |
| `screenshots-captioned/iphone-duo-inner/` | With a headline | 2853 × 2007 | 2 |
| `screenshots/iphone-6.9/`, `iphone-duo-outer/`, `iphone-duo-inner/` | The same, plain | same sizes | 6, 6, 2 |

The iPhone 6.9" set is the required one. Order in each: lists, Today,
calendar, typing a date, scheduled steps, privacy.

| File | What | Use |
|---|---|---|
| `video/app-preview-iphone-886x1920.mp4` | A real recording of the app, 28 seconds | App Preview for iPhone 6.9" |
| `video/app-preview-iphone-duo-1920x886.mp4`, `video/iphone-duo-fold-vertical-1080x1920.mp4` | Animations of the phone folding | Website and social only. Apple asks for captured footage, so these are not App Previews |

Still to take: a third open-Duo picture (the calendar) and an open-Duo
recording. Both need the simulator set to Open in Device Hub; tell me when
you are at the Mac and click Open when I ask.

The older pictures are in `screenshots/_old-2026-11-11/`. They show the old
design and names. Do not upload them.

## 4. In-app purchases (after the Paid Apps Agreement is active)

Subscription group: `Do. Plans`

| Product ID | Type | Reference name | Display name | Description | Price (US) |
|---|---|---|---|---|---|
| `io.github.doproductivity.do.monthly` | Auto-renewable, 1 month | Do. Monthly | Monthly | Everything in Do., month by month. | $2.99 |
| `io.github.doproductivity.do.yearly` | Auto-renewable, 1 year | Do. Yearly | Yearly | Everything in Do., a year at a time. | $9.99 |
| `io.github.doproductivity.do.lifetime` | Non-consumable | Do. Founding member | Founding member | For founding members. Do. is yours for good. | $29.99 (never shown for sale; see below) |

These IDs are already in the app. Type them exactly.

Your decisions when you create them:

- **Prices are the same everywhere,** as you asked: set the US price and leave
  every other country on Apple's automatic equivalent. Do not override Egypt.
- **Family Sharing** for the two plans: on or off.
- **The price of the Founding member product.** Nobody is offered it; founding
  members redeem it free with an Apple code. It still needs a price in App
  Store Connect. I suggest $29.99, well above a year of the yearly plan, so it
  can never undercut it.

In the subscription group, put Yearly above Monthly (level 1 and level 2).

Later, once all three are approved: the free offer codes for founding
members and the two 25% codes for invited people. The steps are at the end of
`FOUNDING-MEMBERS.md`.

## 5. App Privacy answers (App Store Connect → App Privacy)

"Collect" in Apple's sense means data leaves the device and you can access it
afterwards.

- **Lists, notes, calendar:** not collected. They stay on the device, or leave
  it encrypted with a key you never receive.
- **Founding seat or invitation:** this is collected. The server keeps a seat
  number and a code for people who take one.

So the honest answer is **Yes, we collect data**, with one item:

| Data type | Used for | Linked to the user? | Tracking? |
|---|---|---|---|
| Identifiers → User ID | App Functionality | No | No |

The store label will read "Data Not Linked to You: Identifiers" instead of
"Data Not Collected". **This is your decision.** If the "Data Not Collected"
label matters more to you than the founding seats, the seats have to go; they
cannot both be true. If you keep the seats, I will make the app's own privacy
file say the same thing before upload (it currently declares nothing).

## 6. Export compliance (asked on the first upload)

The app encrypts synced lists with standard algorithms that are part of iOS.
Apple will ask whether the app uses encryption. The usual answer for this
case is: yes, and it qualifies for the exemption because it only uses
standard encryption provided by the operating system. This is a legal
declaration and it is yours to make; if you are unsure, Apple's own help page
on export compliance walks through it.

## 7. Notes for App Review (paste into "Notes")

```
Do. needs no account and no sign-in. All features work on first launch.

Calendar: the Calendar list asks for calendar access only when the reviewer taps the line offering it. The app reads events to show them beside tasks and never modifies them.

Plans: the app is free for 14 days. To see the plans without waiting, open Sync, scroll to Membership, and tap "See the plans". Restore Purchases is on the same screen.

Founding members (in Sync): this does not unlock anything in the app. It records an anonymous seat number. Free access for those members is delivered later as App Store offer codes, redeemed through the App Store.

Sync: optional. "Start syncing from this device" needs no account. Data is encrypted on the device before upload.
```

Contact details for review (name, phone, email) are yours to enter.

## 8. What is left, in order

Yours:

1. **Enable your iPhone on the developer account** (developer.apple.com →
   Certificates, IDs & Profiles → Devices). Until then I cannot install on it.
2. **App Store Connect → Business:** accept the Paid Apps Agreement, fill in
   tax and bank details. Then enrol in the Small Business Program.
3. **Create the app record** (section 1) and the two products (section 4).
4. **Decide the privacy label** (section 5).
5. **Send me the support email** for the support and privacy pages.

Mine, when you say go:

1. Put the email on the pages and publish.
2. Switch the paywall on (it must stay off until the products exist), test
   both purchases and Restore in the sandbox, and align the privacy file.
3. Upload the build to App Store Connect.
4. Retake any screenshot that changed.

Then you press Submit for Review.

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
`The first 1,000 founding members get Do. free for life. Take a seat in the app.`

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
Everything works free for 14 days. After that, choose a one-time lifetime purchase or a monthly plan. Whatever you choose, the lists you wrote stay yours to read and export.

Questions: https://do-productivity.github.io/support/
```

## 3. Screenshots (ready, in `brand/app-store/screenshots/`)

All are real captures from Apple's simulators with invented tasks, the clock
at 9:41, and no transparency.

| Folder | Size | Count | Where it goes |
|---|---|---|---|
| `iphone-6.9/` | 1320 × 2868 | 6 | iPhone 6.9" Display (required) |
| `iphone-duo-outer/` | 1398 × 2034 | 6 | iPhone Duo, closed |
| `iphone-duo-inner/` | 2853 × 2007 | 2 | iPhone Duo, open |

Order in each set: lists, Today, calendar, typing a date, scheduled steps,
privacy. A third open-Duo picture (the calendar) needs the simulator set to
Open in Device Hub; ask me and click Open when I say.

The older captioned pictures are in `screenshots/_old-2026-11-11/`. They show
the old design and names. Do not upload them.

The two iPhone Duo films in `brand/app-store/video/` are animations, not
captured footage. Use them on the website and social, not as App Previews.

## 4. In-app purchases (after the Paid Apps Agreement is active)

Subscription group: `Do. Plans`

| Product ID | Type | Reference name | Display name | Description | Price (US) |
|---|---|---|---|---|---|
| `io.github.doproductivity.do.monthly` | Auto-renewable, 1 month | Do. Monthly | Monthly | Everything in Do., month by month. | $2.99 |
| `io.github.doproductivity.do.lifetime` | Non-consumable | Do. Lifetime | Lifetime | Everything in Do., paid once. | $9.99 |

These IDs are already in the app. Type them exactly.

Your decisions when you create them:

- **Egypt price.** Leave Apple's automatic price for Egypt (it follows the US
  price), or set your own. You told me to show dollar pricing in the guide, so
  I have assumed automatic.
- **Family Sharing** for the lifetime plan: on or off.

Later, once both are approved: the free lifetime offer codes for founding
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

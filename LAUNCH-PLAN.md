# Do. — taking it to the App Store

> **The full plan, with screenshots, hosting options and the complete cost
> model, is [Do-launch-plan.pdf](Do-launch-plan.pdf).** Rebuild it with
> `python3 brand/launch-plan/make_pdf.py`, and rebuild its screenshots with
> `node brand/launch-plan/make_shots.mjs` (which seeds invented data — never
> your own). This file is the working text the PDF is drawn from.

The name is **Do.** — the mark that is already on the icon.

Goal: a paid app, **$9.99 once** worldwide and **EGP 99 once** in Egypt, sold on
what it does when the phone unfolds.

This plan is written in the order the risks actually bite, not in the order the
work feels exciting. The first section is the one that can stop everything.

*Revised 10 November 2026, after the calendar shipped.*

---

## 0. What changed since the first draft

The first draft of this plan described a to-do app. In the day since, Do. became
something harder to dismiss — and the change is big enough that it moves both the
App Review risk and the price argument.

| Added | What it is |
|---|---|
| **A calendar** | A sixth panel and a real one: day and week views, a strip of the next seven days, the current-time line, tap an empty slot to create. |
| **Your actual meetings** | Not just dated tasks. The real events from the real calendars on the phone. |
| **Five widgets** | Up from three, and now on the **lock screen** as well as the home screen — your next meeting, or your lists, under the clock. |

That turns the product from *a nicer Reminders* into **the only place your tasks
and your meetings sit on the same timeline** — which is a thing neither Reminders
nor Calendar does, because Apple ships them as two separate apps.

---

## 1. Where the product actually is

Working today, on the device:

- Four lists, natural-language dates, notes, scheduled tasks with steps
- **74 date-parser tests** and **11 ICS parser checks** passing
- Offline by default, no account required
- Local notifications scheduled by iOS — they fire with the app closed
- **A calendar**, with real events (below)
- **Five widgets**: home screen, Today view, and lock screen
- The folding layout, verified at eight widths by an automated harness
- Signed and running on the folding iPhone

Not started: the App Store listing, and the native hardening in section 2.

### How the calendar gets real events

Three routes, and the app picks whichever is available, in this order:

| Route | Where it works | What it takes |
|---|---|---|
| **A subscribed link (ICS)** | Everywhere — Mac, web, phone | Paste a calendar's address once |
| **EventKit** | iPhone only | One permission prompt; then *every* account already set up on the phone — Outlook, iCloud, Gmail — arrives in one list |
| **Microsoft Graph** | Built, not usable | Needs an Entra app registration and a company admin's consent |

EventKit is the one that matters, and it is worth understanding why it is such a
good deal. On the web, every calendar provider is its own integration: a
Microsoft app registration, a Google Cloud project, and nothing at all for
iCloud, which has no public API. On the phone, iOS has already done that work —
whatever accounts exist in Settings, EventKit hands over behind a single prompt.
**This is a capability the web version structurally cannot have**, which makes it
both a selling point and a Guideline 4.2 argument.

**Calendar access is read-only, deliberately.** EventKit will delete an event as
readily as it will read one, and deleting a meeting you organise sends
cancellation emails to everyone on it. A to-do app that can do that by accident
is a bad idea however carefully it is written. Writing is a decision to be made
on purpose, not a capability to leave lying around.

### The engineering discipline already in place

- **A preflight that blocks releases** — it refuses to stamp a build if the
  script will not compile, if element ids are missing or duplicated, if the
  stylesheet is unbalanced, or if the build id disagrees across files.
- **A browser harness** checking layout containment, core flows and search at
  every width that matters.
- **Tests extracted from the shipping file by marker comment**, so the tested
  code is always the shipped code.
- **An error dot** on the device: uncaught errors are recorded and shown,
  because the failure mode of this app is silence.

### Two bugs worth remembering

Both were silent, and both are the same shape — iOS accepting something and
quietly substituting a placeholder rather than failing:

1. **No Capacitor plugin was ever registered.** Capacitor 7 removed the
   Objective-C runtime scan that used to find plugins automatically. An
   unregistered plugin does not complain; it is simply absent. The widget bridge
   had never once worked. One line printing `Object.keys(window.Capacitor.Plugins)`
   found it.
2. **The lock-screen widgets showed "Please adopt containerBackground".** iOS 17
   requires every widget family to declare a background; it was applied only to
   the home-screen branch. Not a build error — WidgetKit swaps in the notice at
   render time.

The lesson for a paid product: **the dangerous failures here are the quiet
ones.** That is what the preflight and the error dot are for, and it is why
anything new gets looked at on real hardware before it is called done.

---

## 2. The gate: Guideline 4.2, Minimum Functionality

**This is the only thing in this document that can stop the whole plan.**
Everything else is a choice; this is a yes or no from Apple.

Apple does not ban a bundled web layer in a native shell. It rejects apps that
are *no more than a repackaged website*, and a reviewer spends about ninety
seconds deciding which one you are.

**The risk has dropped materially since the first draft.** What is now in our
favour:

| In our favour | Why it matters |
|---|---|
| The web code is **bundled**, not fetched from a server | A locally bundled hybrid is a different thing to a webview pointed at a URL |
| **EventKit calendar access** | Reads the phone's real calendar accounts — a website cannot do this at all |
| **Five WidgetKit widgets, including lock screen** | Accessory families under the clock; emphatically not web content |
| Real local notifications | Scheduled by iOS, fire offline with the app closed |
| Genuine offline behaviour | No browser error page, no spinner, no login that forgets you |

**What still looks like a website.** The due date field is a raw
`<input type="datetime-local">`, which is why the phone shows `dd/mm/yyyy, --:--`.
That grey web control in an otherwise carefully made screen is exactly the signal
reviewers are trained on: *web content that is not formatted for iOS*. It is also
simply worse than the native control, so fixing it is not a compliance chore.

What I would add before submitting — each is something a website cannot do,
which is the actual test:

| # | Addition | Effort | Why |
|---|---|---|---|
| 1 | **Native date and time picker** | 1 day | Removes the one visible flaw |
| 2 | **App Intents and Siri** | 2 days | "Add buy milk to Personal"; also Shortcuts and the Action button |
| 3 | **Spotlight indexing** | 1 day | Tasks findable from home screen search |
| 4 | **Share extension** | 1 day | Share a message or page, it becomes a task |
| 5 | Live Activity | 2 days | A running scheduled task counting down in the Dynamic Island |
| 6 | Focus filters | 1 day | Work Focus shows Business only |
| 7 | Native swipe actions and haptics | 1 day | The list feels like a list, not a page |

1–4 are the minimum I would submit on. 5–7 are what make it worth **$9.99**
rather than merely approvable.

**The deeper question, stated once and then dropped.** A web layer is a ceiling
on how iOS the app can ever feel, and at $9.99 you compete with apps that are
native to the bone. The alternative is rebuilding the interface in SwiftUI over
the same model: weeks, and it throws away something that works beautifully today
and deploys in sixty seconds. **I would not do it yet.** Ship the hardened
hybrid, find out whether people buy it, and let revenue — not taste — decide.
But go in knowing the ceiling is there.

---

## 3. What you are actually selling

Not "a to-do app." There are thousands, and Apple gives Reminders away.

Two things now, and they reinforce each other:

**One — the fold.** The only to-do app designed on a folding iPhone from the
first line of CSS. True, unusual, and *visual* — demonstrable in fifteen seconds
with no words, which is what makes it marketable in a way "better task
management" never is.

| state | viewport | what the app does |
|---|---|---|
| folded | 373 × 603 | one list, card fan to switch, tucks away as you read |
| unfolded | 867 × 594 | **three columns, side by side** |
| unfolded wide | 1114 × 594 | four columns, including Scheduled tasks |

No reload, no separate iPad build, no "optimised for" asterisk. The layout is
containment-based rather than pixel-based, which is why it survives the hinge.
Verified at 320, 373, 430, 718, 900, 1114, 1280 and 1440 on every change.

**Two — the whole day in one place.** Apple ships tasks and meetings as two
separate apps and leaves you to hold both in your head. Do. puts them on one
timeline: your 10:30 design review and your "send the budget by four" in the same
column, in the order they will actually happen.

The honest framing for the store listing is not "a to-do app with a calendar." It
is: **the day you actually have, on a phone that opens.**

---

## 4. Price and economics

**Structure:** paid up front, one purchase, no subscription, no in-app
purchases. It matches the product's character and it is what you asked for.

**Enrol in the App Store Small Business Program before the first sale.** It is
not automatic. It takes the commission from 30% to **15%** for developers under
$1M a year, which is you.

| | $9.99 tier | EGP 99 tier |
|---|---|---|
| Apple takes (SBP, 15%) | ~$1.50 | ~EGP 15 |
| you receive | **~$8.49** | **~EGP 84** |
| at 30%, if you forget to enrol | $6.99 | EGP 69 |

Forgetting to enrol costs you $1.50 on every single sale. Do it first.

**Regional pricing is supported.** Apple lets you set a base price and override
it per storefront, so $9.99 globally with EGP 99 in Egypt is a normal
configuration. *Unverified:* I could not confirm Apple's exact EGP price points
from here — 99 may need to round to the nearest available one. Check the price
grid in App Store Connect.

**On the price being defensible.** $9.99 against a free, pre-installed Reminders
was a hard argument when the pitch was "nicer lists." It is a better one now. The
calendar is the feature people pay for in Fantastical and Structured, and the
fold is something nobody else has. That does not make it easy — Things 3 sets the
craft bar — but the thing being sold is now larger than the thing being compared
to.

---

## 5. Sharing it before the App Store

You asked whether the App Store is the only route. It is not, and the answer
shapes the beta.

**The web link — today, free, anyone.** `ahmedmohsen18.github.io/my-todo-list`
is public. Open in Safari, Share → Add to Home Screen, and it behaves like an
app: icon, full screen, offline, data private to that browser. They get the
lists, the calendar panel and the whole fold layout. They do **not** get the
widgets, the lock screen, EventKit, or reliable reminders — web push needs Sync
and a token, which is not something you hand a friend.

**TestFlight — the real answer, and it needs the $99.**

| | |
|---|---|
| external testers | **10,000**, via a public link you can post anywhere |
| internal testers | 100, with 30 devices each |
| what a tester does | install TestFlight, tap the link — no UDIDs, no cable |
| review | a light Beta App Review on the first build of a version, usually about a day |
| build lifespan | 90 days |

No listing, no public launch, no ratings. You can run a ten-thousand-person beta
without ever shipping.

**What you have now cannot be shared.** Free Apple ID provisioning means 7-day
profiles and the device must be plugged into this Mac. Ad Hoc distribution (100
devices, collect every UDID, re-sign per device) is strictly worse than
TestFlight in every respect. Ignore it.

**The two features the price rests on — the widgets and the lock screen — cannot
be shown any way but TestFlight.** That is the trigger to enrol.

---

## 6. The work, in order

**Phase 0 — enrol (you, ~1 day to 1 week)**
Apple Developer Program, $99/year. Enrol with **one Apple ID and stay on it**; we
have already lost time to having two. Individual enrolment needs no D-U-N-S
number; a company one does, and takes longer. Your name appears on the listing
for an individual account.

*Side effect worth having:* the 7-day expiry dies the moment we sign with a paid
team — profiles go to 365 days.

**Phase 1 — native hardening (me, ~1 week)**
Items 1–4 from section 2, each behind the existing `NATIVE` guard so the web
version is untouched and keeps deploying in sixty seconds.

**Phase 2 — rename to Do. (me, ~1 hour, but do it first)**
The app is still called *My To Do List* on the home screen and in the widget
gallery, while everything inside it says **Do.** Every screenshot and every frame
of video will show that name. Change it before a single asset is made.

**Phase 3 — the fold, deliberately (me, ~2 days)**
The layout already adapts. This makes it *perform*: tune the unfold transition so
columns arrive with intent, make sure state survives the hinge, test half-open.
This is the footage.

**Phase 4 — beta (both, ~1 week)**
TestFlight, 10–20 people, at least three on folding hardware. Watch where they
stop.

**Phase 5 — store assets (me + you, ~3 days)**
Screenshots, preview videos, description, keywords, privacy nutrition label.

**Phase 6 — launch and marketing (section 7)**

Realistic first submission: **4–6 weeks** from the day you enrol.

---

## 7. The videos

Three different things, for three different places. Do not try to make one film
do all three jobs.

### A. The hero film — 60–75s, for your site, X, LinkedIn, YouTube

One idea: *the app is the shape of your phone.*

| # | shot | notes |
|---|---|---|
| 1 | Black. A folded phone, screen off, on a paper-coloured surface. | match the app's `#f7f3e9` — the brand is a colour before it is a logo |
| 2 | Thumb wakes it. **The lock screen already says what's next.** | the widget earns its place in the first five seconds |
| 3 | Open. One list. A task gets ticked. | real hands, real speed, no sped-up footage |
| 4 | Swipe to the calendar. The morning's meetings are already there. | this is the "wait, it does that?" beat |
| 5 | Push the list up — the card fan tucks away, the list fills the phone. | the detail that says *somebody thought about this* |
| 6 | **The unfold.** Continuous take. One column becomes three. | no cut. The cut is what viewers assume hides the reload |
| 7 | Fold it shut mid-task. Open again — exactly where you were. | state survival proves it is one app, not two |
| 8 | Home screen, the widget, the icon. Title card. | |

Shot 6 is the whole film. Budget half your shooting time for it. Shot 4 is the
one that changed since the last draft, and it is what justifies the price.

**Voice:** none, or one line at the end. The app's own typography is the brand —
Iowan Old Style on paper. Let the screen talk.

**Music:** single piano or guitar motif, one note landing exactly on the unfold.

**How we capture it:** screen recording comes off the device over the cable
(QuickTime, 60fps, full resolution) — clean pixels but no hands. The physical
unfold needs a camera. Shoot both and composite: camera for the hinge, screen
capture for the pixels, tracked onto the panel. Any editor can do this; it is the
one thing worth paying a freelancer for if you do not want to learn it.

### B. App Store preview videos — up to 3, 15–30s each

Different discipline: **no hands, no voiceover, autoplay muted, first second must
land.** Captured on-device only — Apple requires real device footage.

1. **The fold.** Folded → unfolded → three columns. 15s. This is the one.
2. **The day.** Calendar: meetings and tasks on one timeline, week strip, tap an
   empty slot to add. 20s.
3. **It tells you.** Lock screen widget, then a reminder arriving. 20s.

### C. Short-form — TikTok / Reels / Shorts, 7–15s

One idea each, hook in the first 0.5s, caption burned in.

- *"Your to-do app wasn't made for this phone. Mine was."* → unfold.
- *"One list. Unfold. Three."* → nothing else.
- *"My tasks and my meetings, same screen."* → the calendar, scrolling one day.
- *"I wrote this for myself in a single HTML file."* → the fold. Builder story;
  the one that gets picked up by developer audiences.
- *"Watch what happens when I close it mid-task."* → fold, open, still there.

Post the unfold shot on its own, repeatedly, with different captions. It is the
only asset that needs no explanation.

---

## 8. Store listing

**Name:** **Do.** Short, ownable, already on the icon. Avoid "My To Do List" —
unsearchable and generic, and still the app's real name today (see Phase 2).

**Subtitle (30 chars):** the fold, or the day. Not both.

**Keywords:** fold, folding, todo, tasks, calendar, agenda, reminders, widget,
lock screen, offline, privacy.

**Screenshots, in order:**
1. Three columns on the unfolded screen — nothing else in the category looks like that
2. The calendar: meetings and tasks on one timeline
3. The lock screen, widget under the clock
4. Folded, one list
5. Natural date entry

**Privacy label — read this before filling it in.** It used to be a pure
advantage. It still is, but it is no longer trivial, because the app now asks for
calendar access.

- Nothing leaves the device unless sync is turned on. No accounts. No analytics.
- **Calendar data is read on the device and never transmitted.** Say so plainly.
- The purpose string is already in `Info.plist`
  (`NSCalendarsFullAccessUsageDescription`) and must keep describing the real
  reason, in one sentence a person understands.
- Declare calendar data as **not linked to the user** and **not used for
  tracking** — which is true, and is the strongest version of this story.

---

## 9. Risks, and what I could not verify

Stated plainly so nobody builds on sand:

- **Apple's exact EGP price points.** Per-storefront pricing exists; whether
  exactly 99 is selectable, I could not confirm. Check App Store Connect.
- **The folding iPhone's official marketing name and specs.** Every search result
  was rumour-grade and they contradicted each other. Use Apple's own name in all
  copy, and take the screen facts from the device in your hand — which is where
  the numbers in section 3 came from.
- **Commission rates may be in flux.** There is litigation that may change App
  Store rates. 15% under the Small Business Program is what is documented today.
- **Calendar permission adds review surface.** A sensitive-data prompt invites a
  reviewer to ask why a to-do app needs it. The answer is good — it shows your
  meetings beside your tasks — but it has to be visibly true in the first screen
  after the prompt, or it reads as data collection.
- **TestFlight builds expire after 90 days**, so a long beta needs re-uploads.
- **Review outcomes are never certain.** Section 2 reduces the 4.2 risk; it
  cannot eliminate it.

---

## 10. The first three things

1. **You:** enrol in the Apple Developer Program, one Apple ID, and enrol in the
   Small Business Program in App Store Connect the same day.
2. **Me:** rename the app to **Do.**, then replace the web date input with a
   native picker. The name has to be right before any asset exists; the picker is
   the one visible flaw.
3. **Both:** shoot the unfold once, roughly, on a phone. Before any polish. If
   those fifteen seconds do not make someone say "wait, do that again," the
   positioning is wrong and we would rather learn it in week one.

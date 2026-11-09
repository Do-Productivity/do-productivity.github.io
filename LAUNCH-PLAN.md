# Taking this to the App Store

Goal: a paid app, **$9.99 once** worldwide and **EGP 99 once** in Egypt, sold on
what it does when the phone unfolds.

This plan is written in the order the risks actually bite, not in the order the
work feels exciting. The first section is the one that can stop everything.

---

## 1. The gate: Guideline 4.2, Minimum Functionality

The app today is one HTML file in a Capacitor shell. Apple does not ban that —
but it rejects apps that are *no more than a repackaged website*, and a reviewer
spends about ninety seconds deciding which one you are.

**We already look like a website in at least one place.** The due field is

```html
<input type="datetime-local">
```

which is why the phone shows `dd/mm/yyyy, --:--`. That grey web control in an
otherwise beautiful screen is precisely the tell reviewers are trained on:
*"web content that is not formatted for iOS."*

What counts in our favour:

| | |
|---|---|
| the web code is **bundled**, not loaded from a server | a locally-bundled hybrid app is a different thing to a webview pointing at a URL |
| real local notifications | scheduled by iOS, fire offline, verified on the lock screen |
| a real WidgetKit widget | three of them, reading the app's own App Group storage |

What is missing, and what I would add before submitting — each of these is a
thing a website *cannot* do, which is the test:

1. **Native date & time entry.** Replace the web input. Highest priority: it is
   the one visible flaw, and it is also just better.
2. **App Intents / Siri.** "Hey Siri, add buy milk to Personal." Also puts the
   app in Shortcuts, Spotlight actions and the Action button.
3. **Spotlight indexing (CoreSpotlight).** Tasks findable from the iPhone home
   screen search. Strong signal of a real app.
4. **Share extension.** Share a message, mail or web page → becomes a task.
5. **Live Activity** for a running scheduled task, with its window counting
   down on the Lock Screen and in the Dynamic Island.
6. **Focus filters.** Work Focus shows Business only; Personal Focus the rest.
7. **Native swipe actions and haptics** on rows, so the list feels like a list
   and not a page.

My honest read: 1–4 are the minimum to submit with confidence. 5–7 are what
make it worth **$9.99** rather than merely approvable.

**The deeper question, stated once and then dropped.** A web layer is a ceiling
on how iOS the app can ever feel, and at $9.99 you are competing with Things 3,
which is native to its bones. The alternative is rebuilding the UI in SwiftUI
over the same model. That is weeks, not days, and it throws away a thing that
currently works beautifully and deploys in sixty seconds. **I would not do it
yet.** Ship the hardened hybrid, see whether people buy it, and let revenue —
not taste — decide whether a rewrite is worth it. But go in knowing the ceiling
is there.

---

## 2. What you are actually selling

Not "a to-do app." There are thousands, and Apple gives Reminders away.

You are selling **the only to-do app that was designed on a folding iPhone from
the first line of CSS.** That is true, it is unusual, and it is visual — which
makes it marketable in a way "better task management" never is.

The measured proof, from your own device:

| state | viewport | what the app does |
|---|---|---|
| folded | 373 × 603 | one list, card fan to switch, tucks away as you read |
| unfolded | 867 × 594 | **three columns, side by side** |
| unfolded wide | 1114 × 594 | three columns with room to breathe |

No reload, no separate iPad build, no "optimised for" asterisk. The layout is
containment-based rather than pixel-based, which is why it survives the hinge.
Verified at 320, 373, 430, 718, 900, 1114, 1280 and 1440 by a harness that runs
on every change.

**That is the whole marketing campaign.** Everything in section 5 is just
finding the most beautiful way to film it.

---

## 3. Price and economics

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

**Regional pricing is supported.** Apple lets you set a base price and then
override it per storefront, so $9.99 globally with EGP 99 in Egypt is a normal
configuration, not a hack. *Unverified:* I could not confirm Apple's exact EGP
price points from here — 99 may need to round to the nearest available point.
Check the price grid in App Store Connect when you get there.

**The honest risk:** $9.99 one-time against a free, pre-installed, perfectly
adequate Reminders app is a hard sell on features alone. One-time pricing also
means no recurring revenue to fund years of iOS updates. It works for Things 3
because the craft is undeniable at first glance. That is the bar — which is
another argument for doing section 1 properly.

---

## 4. The work, in order

**Phase 0 — enrol (you, ~1 day to 1 week)**
Apple Developer Program, $99/year. Enrol with **one Apple ID and stay on it**;
we have already been bitten by having two. Individual enrolment needs no D-U-N-S
number; a company one does, and takes longer. Your name appears on the store
listing for an individual account.

*Side effect worth having:* the 7-day expiry dies the moment we sign with the
paid team — profiles go to 365 days. That alone was what you asked for before
this conversation turned into a product plan.

**Phase 1 — native hardening (me, ~1 week)**
Items 1–4 from section 1, each behind the existing `NATIVE` guard so the web
version is untouched and keeps deploying in sixty seconds.

**Phase 2 — the fold, deliberately (me, ~2 days)**
The layout already adapts. This phase makes it *perform*: tune the unfold
transition so columns arrive with intent rather than snapping, make sure state
survives the hinge, and test with the device half-open. This is the footage.

**Phase 3 — beta (both, ~1 week)**
TestFlight, 10–20 people, at least three on folding hardware. Watch where they
stop.

**Phase 4 — store assets (me + you, ~3 days)**
Screenshots, preview videos, description, keywords, privacy nutrition label
(ours is a good story: nothing leaves the phone unless you turn on sync).

**Phase 5 — launch and marketing (section 5)**

Realistic first submission: **4–6 weeks** from the day you enrol, assuming the
app keeps working while we add to it.

---

## 5. The videos

Three different things, for three different places. Do not try to make one film
do all three jobs.

### A. The hero film — 60–75s, for your site, X, LinkedIn, YouTube

One idea: *the app is the shape of your phone.*

| # | shot | notes |
|---|---|---|
| 1 | Black. A folded phone, screen off, on paper-coloured surface. | match the app's `#f7f3e9` — the brand is a colour before it is a logo |
| 2 | Thumb wakes it. One list. A task gets ticked. | real hands, real speed, no sped-up footage |
| 3 | Push the list up — the card fan tucks away, the list fills the phone. | this is the detail that says *somebody thought about this* |
| 4 | **The unfold.** Continuous take. One column becomes three. | no cut. The cut is what viewers assume hides the reload |
| 5 | Hold on three columns. Drag a task between lists. | |
| 6 | Fold it shut mid-task. Open again — exactly where you were. | state survival is the proof it is one app, not two |
| 7 | Lock screen. A reminder arrives. | "it tells you, it doesn't wait to be checked" |
| 8 | Home screen, the widget, the app icon. Title card. | |

Shot 4 is the whole film. Budget half your shooting time for it.

**Voice:** none, or one line at the end. The app's own typography is the brand —
Iowan Old Style on paper. Let the screen talk.

**Music:** single piano or guitar motif, one note landing exactly on the unfold.

**How we capture it:** screen recording comes off the device over the cable
(QuickTime, 60fps, full resolution) — perfectly clean pixels but no hands. The
physical unfold needs a camera. So shoot both and composite: camera for the
hinge, screen capture for the pixels, tracked onto the panel. Any editor can do
this; it is the single thing worth paying a freelancer for if you do not want to
learn it. `xcrun devicectl device capture` also grabs the device screen, which I
can drive from here for stills.

### B. App Store preview videos — up to 3, 15–30s each

Different discipline: **no hands, no voiceover, autoplay muted, first second
must land.** Captured on-device only — Apple requires real device footage.

1. **The fold.** Folded → unfolded → three columns. 15s. This is the one.
2. **Capture speed.** Type "call mum tomorrow 6pm", the date sets itself. 20s.
3. **It tells you.** Reminder on the lock screen, widget on the home screen. 20s.

### C. Short-form — TikTok / Reels / Shorts, 7–15s

One idea each, hook in the first 0.5s, caption burned in.

- *"Your to-do app wasn't made for this phone. Mine was."* → unfold.
- *"One list. Unfold. Three."* → nothing else.
- *"I wrote this for myself in a single HTML file."* → the fold. Builder story;
  this is the one that gets picked up by developer audiences.
- *"Watch what happens when I close it mid-task."* → fold, open, still there.

Post the unfold shot on its own, repeatedly, with different captions. It is the
only asset that needs no explanation.

---

## 6. Store listing

**Name:** avoid "My To Do List" — unsearchable and generic. Something short and
ownable, with the subtitle doing the work. The in-app "Do." mark is already
strong; a name built around it is worth considering.

**Subtitle (30 chars):** the fold, or the speed. Not both.

**Keywords:** fold, folding, todo, tasks, reminders, widget, offline, privacy.

**Screenshots:** the first one decides everything. Lead with three columns on
the unfolded screen — it is the only screenshot in the category that looks like
that.

**Privacy label:** a genuine advantage. Nothing leaves the device unless you
turn on sync; no accounts required; no analytics. Say so, prominently.

---

## 7. What I could not verify

Stated plainly so nobody builds on sand:

- **Apple's exact EGP price points.** Per-storefront pricing exists; whether
  exactly 99 is selectable, I could not confirm. Check App Store Connect.
- **The folding iPhone's official marketing name and specs.** Every search
  result was rumour-grade and they contradicted each other. Use Apple's own name
  for the device in all copy, and take the screen facts from the device in your
  hand — which is where the numbers in section 2 came from.
- **Commission rates may be in flux.** There is litigation that may change App
  Store rates. 15% under the Small Business Program is what is documented today.
- **Review outcomes are never certain.** Section 1 reduces the 4.2 risk; it
  cannot eliminate it.

---

## 8. The first three things

1. **You:** enrol in the Apple Developer Program, one Apple ID, and enrol in the
   Small Business Program in App Store Connect the same day.
2. **Me:** replace the web date input with a native picker, and add App Intents.
   That is the visible flaw and the strongest native signal, in that order.
3. **Both:** shoot the unfold once, roughly, on a phone. Before any polish. If
   that fifteen seconds does not make someone say "wait, do that again," the
   positioning is wrong and we would rather learn it in week one.

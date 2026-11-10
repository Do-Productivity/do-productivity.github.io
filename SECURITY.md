# Security

What Do. holds, who would want it, what is now closed, and what is left open
on purpose. Written 10 November 2026, against build `2026-11-10-2307`.

This is not a reassurance document. Where something is weak, it says so.

---

## What is actually worth stealing

Three things, in order of how much damage losing them does:

1. **The GitHub sync token.** Scope `gist`, which is GitHub's smallest unit
   here — but it reads and writes *every* gist on the account, not only Do.'s.
2. **The tasks themselves.** A to-do list is a map of someone's life: who they
   owe money to, when the house is empty, which doctor, which lawyer.
3. **The calendar.** Only ever read, never stored anywhere but this device —
   but while it is on screen it is the same kind of information.

There is no money in the app to steal. There is no card number anywhere in it,
and there never will be — see **Money** below.

## Who realistically attacks a personal to-do app

Not a targeted adversary. Realistically:

- **A hostile calendar invitation.** Anyone can send you one, and its contents
  arrive inside the app without you deciding anything. This is the only route a
  stranger has into Do. at all, which makes it the one that mattered most.
- **A leaked sync URL** — a screenshot, a shared screen, a support thread.
- **Someone holding the unlocked phone.**
- **Whoever can read the GitHub account.**

Nothing here warrants defending against a government. It does warrant making
the first two impossible or harmless, which is what the work below did.

---

## What the app had going for it already

Worth stating, because it is why the fixes were small:

- **No third-party code at all.** No CDN, no analytics, no ad SDK, no fonts
  fetched from anyone. The entire app is one file. There is no supply chain to
  poison.
- **The interface is built with `createElement` and `textContent`**, not string
  concatenation. One `innerHTML` in the whole file, and it is a fixed sentence
  with nothing interpolated into it. The usual way web apps get owned is simply
  not present.
- **No `eval`, no `new Function`, no `document.write`.**
- **No secrets in the repository**, which matters because GitHub Pages requires
  it to be public. The server-side keys live in environment variables; history
  is clean too.
- **Zero `console.log` calls**, so nothing leaks into a device log — and the
  native bridge is told to keep quiet too (see 5 below; it was not, at first).
- **The Supabase key in the file is the publishable one** — that is its job.
  Row-level security is on with no policies, which is deny-everything, and the
  only way in is three `security definer` functions granted narrowly.

## What was closed

### 1. A calendar invitation could run code in the app — fixed

An event carries a URL, and the app offered to open it. That URL was written by
whoever created the meeting. `javascript:` and `data:` URLs run **in the app's
own origin**, which is where the sync token lives, so a hostile invitation was
enough to read it.

Now only `http:` and `https:` are ever opened, the check runs before the button
is drawn — so there is no button that refuses on tap — and the opened tab is cut
loose with `noopener` so the page it lands on cannot navigate Do. somewhere else.

*Verified:* a seeded `javascript:` invite and a `data:` invite both produce no
link button, a normal `https:` one does, and nothing executed.

### 2. A hostile feed could hang the app — fixed

A subscribed calendar is somebody else's file and is as large as they care to
make it. Fetches are now capped at **4 MB** — about a decade of a busy calendar
— and anything larger is refused rather than parsed on a phone.

### 3. Nothing stops an injected script — fixed, and this is the real one

The app now carries a **Content-Security-Policy** that names its own inline
script by SHA-256 hash and forbids everything else. No CDN, no injected tag, no
`javascript:` URL that slips through a future sanitiser. `default-src` is
`'none'`; `object-src`, `base-uri` and `form-action` are closed.

The hash changes on every build, because the build id lives inside the script.
So:

- `bump-build.py` recomputes it after stamping, as its last act;
- `preflight.js` **fails the build** if the policy and the script have drifted,
  because a mismatch is not a subtle bug — it is a blank page on every device at
  once.

*Verified:* an injected inline script does not run, an external CDN script does
not load, and the browser reports both as policy violations. The app itself runs
clean — no violations on the web and none in the iOS shell, where the Capacitor
bridge still works because `WKUserScript` injection is not subject to page CSP.

`connect-src` allows any `https:` host deliberately. A calendar feed can live
anywhere, and an allow-list would break the moment somebody pasted their own.

### 4. The sync token sat in `localStorage` — moved to the Keychain on iOS

Four things are secrets: the GitHub sync token, the cloud session, the feed
token and the Microsoft calendar session. On the iPhone they now live in the
**Keychain**, through a small native plugin (`SecureStore.swift`), stored
`AfterFirstUnlockThisDeviceOnly` and not synchronised — so they are encrypted
with the device, never ride along in an iCloud or computer backup, and are no
longer sitting in the web view's storage file.

The move happens by itself on first launch of the new build: anything found in
`localStorage` is written to the Keychain and the `localStorage` copy is deleted
**only after the Keychain confirms the write**. If the Keychain ever refuses, the
value stays where it was rather than being lost, and the Sync sheet says
"partly" instead of pretending. The Sync sheet shows which of the three states
the device is in.

What this does and does not buy, stated plainly:

- It protects the token **at rest** — from a backup, from another app, from
  someone pulling files off the phone.
- It does **not** protect it from script running inside the app. The app has to
  be able to read its own token, so anything that could run code in the page
  could ask for it. The Content-Security-Policy above is the defence against
  that, not the Keychain.
- **On the web there is no Keychain.** The browser version still keeps the token
  in `localStorage`, bound to the origin. That is as good as a web page gets.

*Verified:* against a mocked bridge — migration, the delete-only-after-confirm
ordering, the refusal fallback, removal on disconnect. In the iOS simulator the
plugin loads, answers, and the Sync sheet reports the Keychain. **Not verified:**
a real token making the round trip on a real phone; that is checked by using the
app, not by reading the Keychain from a computer.

### 5. The native bridge was logging every call — silenced

Capacitor, in a debug build, prints every message between the web layer and
Swift to the device console, results included. The build that goes onto the
phone over the cable *is* a debug build, so the moment the Keychain plugin
existed, its answer — the token — would have been printed to a log anyone with
the phone and a Mac could read. `loggingBehavior` is now `none`.

This one was found by looking at the simulator's console rather than by
reasoning, which is the argument for looking.

---

## What is open, on purpose

### The web version keeps the sync token in `localStorage`

On the iPhone it is in the Keychain now (4, above). In a browser there is
nowhere better to put it: it is bound to the origin, and the realistic way to
steal it is cross-site scripting, which the policy above makes very hard.

### A "secret" gist is unlisted, not private

`public: false` means GitHub will not list or index it. **Anyone who has the URL
can read it**, with no GitHub account at all. That is security by unguessable
URL, which is a real defence — it is 32 random hex characters — but it means:

- the sync URL must never be shared or screenshotted;
- anyone who can read the GitHub account can read every task;
- the tasks sit there in plaintext.

**The fix is to encrypt `tasks.json` before it is uploaded**, with a key derived
from a passphrase that never leaves the device. Then a leaked URL yields noise.
Not built.

### The published `reminders.ics` is readable by anyone who has its address

This one cannot be fixed without losing the feature. Apple Calendar subscribes
to that URL, so it has to be fetchable by Apple's servers, and it has to be
plaintext because Calendar has to parse it. Every dated task title is in it.

So: that address is a secret, it travels to Apple, and it is the single most
exposed thing in the app. It is a deliberate trade for reminders that ring on
time on every device, and it should be described in those words in the app.

### A jailbroken device wins

It always does, for every app. See below.

---

## Money

The purchase layer is **built and switched off**. `StoreBridge.swift` holds the
whole of it — the products, the thirty-day clock, the paywall — behind one
constant, `Store.enforced = false`. While it is false nobody is ever asked to
pay and nothing is gated. It stays false until the two products exist in App
Store Connect, because an enforced paywall with nothing on sale behind it is a
locked door with no handle.

These are the rules it was built to, and they are rules rather than suggestions
because the mistakes here are expensive.

**For the user's money — the only one that really matters:**

- **There will never be a payment form in the web layer.** Not a card field, not
  a "confirm your details" screen, nothing that looks like one. The paywall is
  native StoreKit UI, and Apple takes the payment. An app that teaches its users
  to type card numbers into its own web view has trained them to be phished.
- **The app never sees a card number, and never will.**
- **If the trial ends, the data stays readable and exportable.** Payment may gate
  features; it must never hold someone's own tasks hostage. That is both the
  decent thing and the thing that avoids a review problem.

**For your money:**

- **Entitlement is decided in Swift**, from StoreKit 2's *verified* transactions
  (`Transaction.currentEntitlements`, checking `VerificationResult.verified`).
  Never from a boolean in JavaScript, never from a flag in `localStorage`, and
  never from anything the web layer hands down. The web layer may be *told* the
  answer; it must not be the one that decides it.
- **The thirty-day trial clock is in the Keychain**, which survives deleting the
  app; `localStorage` does not. It was meant to be in iCloud key-value storage
  as well, so that a second device shares the clock. **That half is not built:**
  iCloud entitlements need the paid developer account. Until then, a new device
  is a new month.
- **A Restore Purchases button is mandatory**, and it is on the paywall. Without
  one, Apple rejects.
- **A jailbroken device will beat all of this**, and that is fine. At a dollar a
  month, anti-tamper engineering costs more than the theft. Build it correctly,
  then stop.

**How it is put together:**

- The paywall is a native SwiftUI sheet. The web layer can ask for it to be
  shown and is told the outcome; it never draws a price, a plan or a button that
  takes money.
- "Paid" is whatever `Transaction.currentEntitlements` returns *verified*.
  Unverified transactions are ignored, not trusted and not argued with.
- The web layer asks the bridge "may this person add things?" and acts on the
  answer. Setting a flag in JavaScript or `localStorage` changes nothing — there
  is a test that tries.
- When it is enforced, the only thing that stops is **adding**: a task, a list, a
  note, a scheduled task, a duplicate. Reading, ticking off, editing, deleting,
  exporting and syncing never stop.

**What is not verified, and why:**

- **No real purchase has ever been made.** The products do not exist yet. In the
  simulator the paywall opens and says the plans are not on sale, which is the
  right answer to having nothing to sell.
- `Do.storekit` is a local test catalogue with the two products in it, wired to
  the shared Xcode scheme. It only takes effect when the app is run *from Xcode*;
  that path has not been exercised.
- The product ids the code expects are `com.ahmedmohsen.todolist.monthly` and
  `com.ahmedmohsen.todolist.lifetime`. The ones created in App Store Connect
  have to match exactly.

**The hole that is a business decision, not a bug:** the web version is the same
app, free, at a public address. A paywall in the iPhone app does not close that.
Either the web version stays as the free tier on purpose, or it comes down when
the App Store version goes up.

---

## Checking this has not regressed

Run before any release:

```bash
node preflight.js
```

It now fails if the Content-Security-Policy and the inline script have drifted
apart, and warns if the policy has been removed entirely.

Worth re-checking by hand whenever the calendar or sync code is touched:

- `grep -c innerHTML index.html` — the answer should be **1**, and that one
  should still be a fixed string.
- `grep -nE "\.href =|window\.open" index.html` — every one of them should
  either be a URL the app built itself, or go through `safeLink()`.
- `grep -rniE "ghp_|github_pat_|BEGIN .*PRIVATE KEY" .` — the repository is
  public. Nothing may match except the placeholder in the token input.

## If a token leaks

1. Revoke it at **github.com/settings/tokens** — this is instant and total.
2. Delete the sync gist, which destroys the copy of the tasks.
3. In Do., disconnect sync; create a new token and a new gist.
4. If the `reminders.ics` address was the thing that leaked, the new gist gives
   it a new address. Re-subscribe on each device and delete the old subscription.

# Keeping this thing stable

One HTML file, no build step, deployed straight to GitHub Pages and reloaded
by every device within a minute. That is what makes it pleasant to work on and
what makes a mistake arrive everywhere at once. These four layers exist so a
mistake has to get past a machine before it reaches a phone.

## 1. Preflight — runs itself, blocks the build

```bash
node preflight.js
```

`bump-build.py` runs it first and **refuses to stamp a build id if it fails**,
so a broken file cannot be deployed by the usual route. A build id is a promise
to every device that polls `version.json`: *take this one, it is better than
what you have.*

It fails on the things that have actually shipped broken here:

| Check | What it would have caught |
|---|---|
| inline script compiles | one stray brace takes the whole app down — it is all one `<script>` |
| `index.html` / `sw.js` / `version.json` agree on the build | devices never hear there is an update |
| `getElementById` ids exist in the page | the Scheduled tab button that was never added: handler compiles, finds nothing, does nothing |
| no duplicate element ids | one of them is unreachable |
| stylesheet braces balanced | every rule after the mistake is silently dropped |
| service worker's SHELL files exist | offline mode caches a 404 |
| test files compile | a broken harness reports "all pass" |

It also *warns* when one selector sets the same property twice inside one media
block. Sometimes deliberate; it is also how "the rule I added did nothing"
happened three times (`.panel { padding }` redeclared in the 440 and 349
blocks). Fallback pairs — `100vh` then `100dvh`, `env()`, `-webkit-` — are not
reported.

To bypass on purpose: `SKIP_PREFLIGHT=1 python3 bump-build.py`.

## 2. The browser harness — behaviour and layout

Open a **local** copy, paste `test-search.js` then `test-app.js` into the
console, and:

```js
runAll()            // layout at this width + core flows + search
runLayoutChecks()   // just the layout invariants, for sweeping widths
```

- **Layout invariants** are the ones that keep breaking, expressed as
  containment rather than as pixel values, so they hold at any size: nothing
  wider than its card, no card outside the window, the page never grows a
  scrollbar, a long list scrolls *inside* the card, the add box and its button
  both fit, the toolbar stays on screen.
- **Core flows**: add, count, tick, untick, delete, restore, a date typed into
  the text, a note against a task, a loose note refused rather than swallowed,
  a scheduled task with a step, Today, and what is on screen matching what is
  stored.
- **Search**: finding and *landing on* every kind of row, including inside shut
  drawers and behind the one-task notes filter.
- **`nothing threw while the suite ran`** reads the app's own error log. An
  assertion can pass while a feature is dead; this catches that.

Sweep the widths that matter — 320, 373 (folded Duo), 430, 718, 900, 1114
(unfolded Duo), 1280, 1440 — with `runLayoutChecks()` after any CSS change.

Two guards, both learned the hard way:

- It **refuses to run on a device that syncs**. Probes are made through the
  real UI, so they reach the account before cleanup, and cleanup deletes from
  `localStorage` *without a tombstone* — the next sync hands them back.
- It **refuses a second run without a reload**. Each panel holds its task array
  in a closure, so a save after a cleanup resurrects rows storage no longer
  has. For the same reason the final sweep lives in `runAll()`, after every
  suite has stopped writing.

## 3. The parser tests

```bash
node test-due-dates.js      # 74 checks: 59 reading, 15 repeat arithmetic
```

These extract the parser and the repeat model *out of `index.html` by marker
comment*, so the tested code is always the shipped code.

## 4. The error dot — the app says when it breaks

Uncaught errors and unhandled rejections are recorded on the device (newest
last, capped, nothing leaves the phone) and a red dot appears next to the build
stamp. Tapping it shows what happened, with the build id and time, and offers
Copy and Clear.

This exists because the failure mode here is silence: the drawer-opening bug
threw on every search, the status line and highlight simply never ran, and the
page looked perfectly fine. The console had it; nobody was looking at the
console on a phone.

## The routine before deploying

```bash
node test-due-dates.js && node preflight.js && python3 bump-build.py
```

then the browser harness on a local copy if anything behavioural or visual
changed, then commit and push. Confirm the deploy actually landed:

```bash
curl -s "https://ahmedmohsen18.github.io/my-todo-list/version.json?cb=$RANDOM"
```

## Known traps, written down so they stop costing time

- **The service worker's catch-all used `ignoreSearch`**, so `?cb=` URLs were
  answered from cache anyway — it served a stale test script three runs in a
  row. Fixed: a request with a query string goes to the network. If you ever
  see edits not taking effect locally, check the service worker before
  believing the code.
- **A detached node's `closest()` is `null`.** Clicking a drawer toggle
  re-renders the panel, so read everything you need from a node *before* any
  click that could re-render it.
- **The browser pane forces mobile emulation under 768px wide**, so it reports
  `pointer: coarse` and cannot verify a `pointer: fine` rule by resizing.
  Inject the declarations unconditionally to check the layout they produce.
- **Screenshots lag the DOM.** Measure with `getBoundingClientRect`, do not
  trust a picture taken mid-animation.

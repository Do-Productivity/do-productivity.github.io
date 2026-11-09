# The iOS app

The same `index.html`, wrapped. Not a rewrite, not a second copy of the UI:
`native/www/index.html` is a byte-identical copy of the file the website
serves, and `preflight.js` warns when it stops being one.

What the wrapper buys, and nothing else does:

| | web app | this |
|---|---|---|
| a reminder at 09:30 | GitHub Actions cron (measured: one run every 60–195 min) → gist → Web Push, or a subscribed calendar feed needing *Fetch New Data = every 15 min* | iOS holds the alarm. Offline, exact, no server |
| the home screen | Scriptable script reading the **public** gist, iOS refresh capped ~5–15 min | a real widget reading the app's own storage |
| storage | `localStorage`, which Safari can evict | the app's own container |

## Building it onto your phone

You need Xcode (27.2 here) and your Apple ID. **No paid account**, so the app
is signed for 7 days and then needs the same Run again — step 5 is the whole
re-signing routine.

The signing team is already set in the project: **`6MCMG3FEW8`**. Note that
this is *not* the number in the certificate's name. The certificate is called
`Apple Development: Ahmed Hassaan (6DSVWXH9GY)`, and `6DSVWXH9GY` is the
certificate id, not a team — putting it in `DEVELOPMENT_TEAM` produces
`No profiles for 'com.ahmedmohsen.mytodolist' were found`, which reads exactly
like a sign-in problem and is not one. The team is the certificate's OU:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

```bash
python3 build-native.py && cd native && npx cap copy ios && open ios/App/App.xcodeproj
```

Then, in Xcode:

1. Select the **App** target → *Signing & Capabilities*.
2. *Team* → your Apple ID. (*Add an Account…* if it is not listed.)
3. If it complains the bundle id is taken, change **Bundle Identifier** to
   something unique — `com.<yourname>.mytodolist` — and make the widget's id
   the same thing with `.TodoWidget` on the end.
4. Do the same for the **TodoWidget** target (select it in the sidebar).
5. Plug the phone in, pick it as the destination, press ⌘R.

The first run asks you, on the phone, to trust the developer:
*Settings → General → VPN & Device Management → your Apple ID → Trust*.

### App Groups on a free team — answered: it works

This was the open question. It is settled: on 9 Nov 2026 the free personal team
minted both profiles carrying `group.com.ahmedmohsen.mytodolist`, and codesign
confirms the entitlement on the app *and* the widget:

```bash
codesign -d --entitlements :- App.app | plutil -p -
```

So the widget reads the app's own storage and refreshes the moment you edit a
task. The public-feed fallback in `TodoWidget.swift` stays anyway — it is what
makes the widget survive a signing problem instead of going blank — but it is
now the second choice, not the expected one.

## Afterwards

```bash
node preflight.js          # warns if the bundle has drifted from index.html
python3 build-native.py --check
```

## Adding the widget

Long-press the home screen → *Edit* → *Add Widget* → search **To Do**. Three
to choose from: everything, Personal only, Business only. Small, medium and
large each show more rows.

## Re-adding the iOS platform

`npx cap add ios` rewrites the Xcode project from Capacitor's template, which
knows nothing about a widget. Afterwards:

```bash
./.tools/bin/python add-widget-target.py
```

That script is the memory of the fifteen clicks: it adds `WidgetBridge.swift`
to the app, creates the `TodoWidget` extension target, embeds it, makes it a
build dependency and points both targets at their entitlements. It is
idempotent — running it twice does nothing the second time. If the venv is
missing:

```bash
python3 -m venv .tools && ./.tools/bin/pip install pbxproj
```

## What is deliberately different inside the shell

`index.html` checks for the Capacitor bridge once (`NATIVE`) and changes three
things:

- **the self-updater is off.** The bundled file cannot climb to a newer build,
  so polling `version.json` would reload for ever. The shell is updated by
  rebuilding it; the Sync panel shows which build it is carrying.
- **the service worker is not registered.** It cannot run on
  `capacitor://localhost`, and there is nothing to cache — the bundle is local.
- **reminders are scheduled with iOS** instead of going the long way round.

## What it deliberately does not do

Tapping a reminder **opens** the task rather than completing it, and there are
no Done/Snooze buttons on the notification. Each panel keeps its task array in
a closure, so writing to storage from outside and not re-rendering gets the
old array saved back over it later — the resurrection trap in `STABILITY.md`.
Notification actions need a cross-panel mutation API first.

#!/usr/bin/env bash
# Put the current index.html on the phone, over the cable. One command.
#
# The web app deploys itself: push, and every device polling version.json
# takes the new build within a minute. The shell cannot do that — its copy of
# index.html is inside the signed bundle, and a bundle can only be replaced by
# building and installing it. So the phone silently keeps running whatever was
# last installed, which is the same stale-cache problem the build stamp exists
# to prevent, only with no way for the phone to notice.
#
# Hence this: after any change to index.html, the phone gets it over the cable.
#
#   ./ship-to-phone.sh            bundle, build, install, launch
#   ./ship-to-phone.sh --no-launch   leave it closed (don't steal the screen)
#
# It does NOT stamp a build id — run bump-build.py first if the change should
# also go to the web. Shipping an unstamped change to the phone on its own is
# fine and often what you want while iterating.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
BUNDLE_ID="com.ahmedmohsen.todolist"
LAUNCH=1
[ "${1:-}" = "--no-launch" ] && LAUNCH=0

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── 1. which phone? ────────────────────────────────────────────────────────
# Discovered, not hard-coded: a re-paired phone gets a new identifier, and a
# stale one fails as "destination not found", which reads like a project
# problem rather than a cable problem.
DEVICE_LINE="$(xcrun devicectl list devices 2>/dev/null | grep -i 'physical' | head -1 || true)"
if [ -z "$DEVICE_LINE" ]; then
  echo "No iPhone is paired with this Mac. Plug it in and unlock it." >&2
  exit 1
fi
UDID="$(echo "$DEVICE_LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)"
NAME="$(echo "$DEVICE_LINE" | sed 's/  */ /g' | cut -d' ' -f1-2)"
if echo "$DEVICE_LINE" | grep -qi 'unavailable'; then
  echo "$NAME is paired but unavailable — the cable is out, or the phone is" >&2
  echo "asleep or locked. Plug it in, wake it, unlock it, and run this again." >&2
  exit 1
fi

# ── 2. the bundle carries the file being shipped ───────────────────────────
say "Bundling index.html"
python3 "$REPO/build-native.py"
( cd "$HERE" && npx cap copy ios )

BUILD="$(grep -o 'var BUILD = "[^"]*"' "$REPO/index.html" | head -1 | sed 's/.*"\(.*\)"/\1/')"

# ── 3. build and sign for this phone ───────────────────────────────────────
# -allowProvisioningUpdates because free signing re-mints the profile every
# seven days; without it the first build after expiry fails instead of
# quietly renewing.
say "Building $BUILD for $NAME"
( cd "$HERE/ios/App" && xcodebuild \
    -scheme App -configuration Debug \
    -destination "id=$UDID" \
    -allowProvisioningUpdates \
    -derivedDataPath ../DerivedData \
    build 2>&1 | grep -E 'error:|warning: .*[Ss]ign|BUILD (SUCCEEDED|FAILED)' || true )

APP="$HERE/ios/DerivedData/Build/Products/Debug-iphoneos/App.app"
[ -d "$APP" ] || { echo "the build produced no App.app — see the output above" >&2; exit 1; }

say "Installing"
xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | grep -E 'App installed|bundleID|ERROR|reason' || true

if [ "$LAUNCH" = "1" ]; then
  say "Launching"
  # The phone has to be unlocked for this; everything above works locked.
  xcrun devicectl device process launch \
      --device "$UDID" --terminate-existing "$BUNDLE_ID" 2>&1 \
    | grep -E 'launched|processIdentifier|ERROR|reason' || true
fi

say "$BUILD is on $NAME"

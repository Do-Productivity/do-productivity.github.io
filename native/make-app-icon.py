#!/usr/bin/env python3
"""Build the iOS app icon from the web app's own icon, so they are the same.

The home screen is the whole point of this: the app icon must be the icon that
is already on the phone. apple-touch-icon.png is 180x180, which is exactly what
an iPhone home screen renders (60pt at 3x), and every other place iOS shows the
icon is SMALLER than that — Spotlight is 120px, Settings 87px, the largest iPad
slot 167px. The asset catalog nevertheless demands a single 1024x1024 image,
which iOS scales back down.

So the question is not "how do I make a 1024 icon", it is "which 1024 image
survives the trip back down to 180 looking most like the original". Measured,
mean absolute difference per channel against the original:

    upscale the original, LANCZOS          0.52 / 255   <- this
    upscale the original, BICUBIC          0.62
    upscale the original, NEAREST          0.56
    redraw it at 1024 from its geometry    5.16

Redrawing loses, and it loses by ten times, however carefully the typeface is
matched (it is Iowan Old Style Bold, the app's own --serif, at the equivalent
of 295pt with the period drawn as a circle rather than set as a glyph). A
redraw is a different rendering; a round trip is almost the same pixels. If the
icon ever needs to be genuinely sharp at 1024 — an App Store listing — redraw
it then, and accept that it will not match the phone exactly.

    python3 make-app-icon.py
"""
import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is missing.  python3 -m pip install --user Pillow")

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "apple-touch-icon.png"
DST = HERE / "ios" / "App" / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-512@2x.png"

if not SRC.exists():
    sys.exit("no source icon at " + str(SRC))

im = Image.open(SRC)
if im.size != (180, 180):
    print("note: source is %dx%d, not the expected 180x180" % im.size)

# RGB, never RGBA: iOS rejects an app icon with an alpha channel, and the
# rejection is silent in some tools — the icon simply does not appear.
im = im.convert("RGB").resize((1024, 1024), Image.LANCZOS)
DST.parent.mkdir(parents=True, exist_ok=True)
im.save(DST, "PNG")
print("wrote %s  1024x1024 RGB" % DST)
print("next: (cd ios/App && xcodebuild ...) or just rebuild the app")

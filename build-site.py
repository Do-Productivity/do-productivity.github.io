#!/usr/bin/env python3
"""Assemble the public website into one folder, ready to publish.

    python3 build-site.py [out folder]        (default: _site)

What goes where:
    /                       the landing page             <- landing/
    /app/                   the web app                  <- index.html, sw.js, manifest.json, version.json, icon
    /support/  /privacy/    the support page and the privacy policy
    /widget/  /size/  /brand/friends-family/   pages that already had an address
    /sw.js                  retires the helper the app used to run at the top address  <- landing/sw.js
    /version.json           so a tab still open on the old address notices there is a new build

The app's own files stay where the tools expect them, at the top of the
repository; only the published copy lives under /app/.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "_site"))
APP_FILES = ["index.html", "sw.js", "manifest.json", "version.json", "apple-touch-icon.png"]
FOLDERS = ["support", "privacy", "widget", "size", os.path.join("brand", "friends-family")]

if os.path.exists(OUT):
    shutil.rmtree(OUT)
shutil.copytree(os.path.join(ROOT, "landing"), OUT, ignore=shutil.ignore_patterns(".DS_Store"))
os.makedirs(os.path.join(OUT, "app"))
for name in APP_FILES:
    shutil.copy2(os.path.join(ROOT, name), os.path.join(OUT, "app", name))
shutil.copy2(os.path.join(ROOT, "version.json"), os.path.join(OUT, "version.json"))
for folder in FOLDERS:
    shutil.copytree(os.path.join(ROOT, folder), os.path.join(OUT, folder),
                    ignore=shutil.ignore_patterns(".DS_Store", "*.py", "*.mjs"))
open(os.path.join(OUT, ".nojekyll"), "w").close()

for must in ["index.html", "sw.js", "app/index.html", "app/sw.js", "support/index.html", "privacy/index.html",
             "media/duo-fold-wide.mp4", "media/duo-fold-tall.mp4"]:
    if not os.path.exists(os.path.join(OUT, must)):
        raise SystemExit("missing from the site: " + must)
if "id=\"today-btn\"" in open(os.path.join(OUT, "index.html"), encoding="utf-8").read():
    raise SystemExit("the top page is the app, not the landing page")
size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
print("site built in %s: %.1f MB" % (OUT, size / 1e6))

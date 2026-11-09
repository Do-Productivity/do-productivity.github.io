#!/usr/bin/env python3
"""Bundle the web app into the iOS shell.

The whole point of the native app is wrap-not-rewrite: `native/www/index.html`
is a BYTE-IDENTICAL copy of the shipped `index.html`. No transformation, no
preprocessor, no second copy of the UI to keep in step — if the two files ever
differ, something is wrong. Everything the native build needs to behave
differently is decided at runtime inside index.html by looking for the
Capacitor bridge (see NATIVE in the script).

What is deliberately NOT copied:

  sw.js        a service worker cannot register on capacitor://localhost, and
               the native bundle is already local — there is nothing to cache.
  version.json the self-updater must stay off in the shell. The bundled copy
               of index.html can never change on its own, so polling a newer
               build id would reload forever. index.html guards this, and
               leaving the file out means a mistake there fails closed.

Usage:
    python3 build-native.py            bundle, then report what was bundled
    python3 build-native.py --check    verify the bundle matches index.html
"""

import hashlib
import json
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent
WWW = ROOT / "native" / "www"
COPY = ["index.html", "manifest.json", "apple-touch-icon.png"]
STAMP = WWW / "native-build.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def build_id():
    m = re.search(r'var BUILD = "([^"]*)"', (ROOT / "index.html").read_text())
    if not m:
        sys.exit("no BUILD constant in index.html — run preflight first")
    return m.group(1)


def check():
    missing = [n for n in COPY if not (WWW / n).exists()]
    if missing:
        return "bundle is missing " + ", ".join(missing)
    for name in COPY:
        if digest(ROOT / name) != digest(WWW / name):
            return name + " in the bundle differs from the one being shipped"
    if not STAMP.exists():
        return "no native-build.json in the bundle"
    if json.loads(STAMP.read_text()).get("build") != build_id():
        return "the bundle was made from a different build of index.html"
    return None


if "--check" in sys.argv:
    problem = check()
    if problem:
        sys.exit("native bundle is stale: " + problem + "\n  run: python3 build-native.py")
    print("native bundle matches index.html (build " + build_id() + ")")
    sys.exit(0)

WWW.mkdir(parents=True, exist_ok=True)
for name in COPY:
    src = ROOT / name
    if not src.exists():
        sys.exit("cannot bundle: " + name + " is missing")
    shutil.copy2(src, WWW / name)

STAMP.write_text(json.dumps({"build": build_id(), "note":
                             "written by build-native.py; the shell shows this "
                             "so a stale bundle is visible at a glance"}) + "\n")

problem = check()
if problem:
    sys.exit("bundled, but the result does not verify: " + problem)

print("bundled build " + build_id() + " -> native/www")
for name in COPY:
    print("  " + name + "  " + str((WWW / name).stat().st_size // 1024) + " KB")
print("\nnext: cd native && npx cap sync ios")

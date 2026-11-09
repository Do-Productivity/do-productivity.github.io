#!/usr/bin/env python3
"""Stamp a new build id into index.html, sw.js and version.json.

Run after editing index.html or sw.js:   python3 bump-build.py

Devices poll version.json and reload themselves when the id changes, so a
phone can't sit on a stale cached copy. The same id names the service
worker's cache, so a new build also retires the old offline copy instead of
letting it linger.
"""
import os
import shutil
import datetime, json, pathlib, re, subprocess, sys

here = pathlib.Path(__file__).parent


def node_bin():
    found = shutil.which("node")
    if not found:
        sys.exit("preflight needs node on PATH (or SKIP_PREFLIGHT=1 to bypass)")
    return found


# Preflight first, and refuse to stamp if it fails. A build id is a promise to
# every device that polls version.json: take this one, it is better than what
# you have. Minting one for a file with a syntax error, an unbalanced
# stylesheet or a handler pointing at an id that is not there turns that
# promise into an outage on every phone at once. Skip it only on purpose:
#   SKIP_PREFLIGHT=1 python3 bump-build.py
if not os.environ.get("SKIP_PREFLIGHT"):
    check = subprocess.run([node_bin(), str(here / "preflight.js"), "--quiet"])
    if check.returncode != 0:
        sys.exit("preflight failed — nothing stamped, nothing deployed")

build = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")

for name in ("index.html", "sw.js"):
    f = here / name
    text = f.read_text()
    text, n = re.subn(r'var BUILD = "[^"]*";', f'var BUILD = "{build}";', text, count=1)
    if n == 0:
        raise SystemExit(f"BUILD constant not found in {name}")
    f.write_text(text)

(here / "version.json").write_text(json.dumps({"build": build}) + "\n")
print("stamped build", build)

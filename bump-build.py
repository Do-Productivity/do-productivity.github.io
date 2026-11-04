#!/usr/bin/env python3
"""Stamp a new build id into index.html, sw.js and version.json.

Run after editing index.html or sw.js:   python3 bump-build.py

Devices poll version.json and reload themselves when the id changes, so a
phone can't sit on a stale cached copy. The same id names the service
worker's cache, so a new build also retires the old offline copy instead of
letting it linger.
"""
import datetime, json, pathlib, re

here = pathlib.Path(__file__).parent
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

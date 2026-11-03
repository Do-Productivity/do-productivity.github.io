#!/usr/bin/env python3
"""Stamp a new build id into index.html and version.json.

Run after editing index.html:   python3 bump-build.py
Devices poll version.json and reload themselves when the id changes, so a
phone can't sit on a stale cached copy.
"""
import datetime, json, pathlib, re

here = pathlib.Path(__file__).parent
build = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")

idx = here / "index.html"
html = idx.read_text()
html, n = re.subn(r'var BUILD = "[^"]*";', f'var BUILD = "{build}";', html, count=1)
if n == 0:
    raise SystemExit("BUILD constant not found in index.html")
html = re.sub(r'Build: <b>[^<]*</b>', f'Build: <b>{build}</b>', html, count=1)
idx.write_text(html)

(here / "version.json").write_text(json.dumps({"build": build}) + "\n")
print("stamped build", build)

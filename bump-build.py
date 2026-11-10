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
import base64, datetime, hashlib, json, pathlib, re, subprocess, sys

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


# The Content-Security-Policy names the inline script by hash, so nothing else
# can execute in this page - and the script just changed, because the build id
# lives inside it. Recompute the hash now, last, or the app ships with a policy
# that forbids its own code and every device loads a blank page at once.
#
# The bytes hashed must be exactly what sits between the script tags: no
# trailing newline of our own, no re-encoding. The browser hashes the raw text.
index = here / "index.html"
html = index.read_text()
m = re.search(r"<script>(.*?)</script>", html, re.S)
if not m:
    raise SystemExit("no inline <script> found in index.html")
digest = base64.b64encode(hashlib.sha256(m.group(1).encode("utf-8")).digest()).decode()
html, n = re.subn(r"'sha256-[^']*'", f"'sha256-{digest}'", html, count=1)
if n == 0:
    raise SystemExit("no Content-Security-Policy script hash to update in index.html")
index.write_text(html)

(here / "version.json").write_text(json.dumps({"build": build}) + "\n")
print("stamped build", build)
print("csp script hash sha256-" + digest[:16] + "...")

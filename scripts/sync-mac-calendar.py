#!/usr/bin/env python3
"""Mirror the to-do feed into a writable macOS Calendar (Exchange) calendar.

The subscribed-calendar route on macOS refreshes on Apple's own slow schedule.
This writes the events directly instead, so the Mac — and, because the target
lives in the Exchange account, Outlook everywhere — stays current.

Usage:  python3 sync-mac-calendar.py [--calendar "My: To Do List"] [--dry-run]
"""

import argparse
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta

FEED = ("https://gist.githubusercontent.com/ahmedmohsen18/"
        "1f3e9c2d3186c395b62391c6b62f0358/raw/reminders.ics")
DEFAULT_CALENDAR = "My: To Do List"


def fetch_feed(url):
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def parse_events(ics):
    """Return [(summary, datetime)] for every VEVENT in the feed."""
    # iCalendar uses CRLF; leaving the \r in breaks every anchored match
    ics = ics.replace("\r\n", "\n").replace("\r", "\n")
    events = []
    for block in ics.split("BEGIN:VEVENT")[1:]:
        block = block.split("END:VEVENT")[0]
        summary = re.search(r"^SUMMARY:(.*)$", block, re.M)
        start = re.search(r"^DTSTART:(\d{8}T\d{6})$", block, re.M)
        if not summary or not start:
            continue
        text = summary.group(1).strip().replace("\\,", ",").replace("\\;", ";")
        when = datetime.strptime(start.group(1), "%Y%m%dT%H%M%S")
        events.append((text, when))
    return events


def osa(script):
    p = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip())
    return p.stdout.strip()


def existing_events(calendar):
    """Summaries already present, so we never create duplicates."""
    out = osa(f'''
tell application "Calendar"
  set acc to ""
  repeat with c in calendars
    if name of c is "{calendar}" then
      repeat with e in events of c
        set acc to acc & (summary of e) & "\\n"
      end repeat
    end if
  end repeat
  return acc
end tell''')
    return {line.strip() for line in out.splitlines() if line.strip()}


def add_event(calendar, summary, when, dry_run=False):
    end = when + timedelta(minutes=0)
    safe = summary.replace('"', "'")
    script = f'''
tell application "Calendar"
  tell calendar "{calendar}"
    set d to (current date)
    set year of d to {when.year}
    set month of d to {when.month}
    set day of d to {when.day}
    set hours of d to {when.hour}
    set minutes of d to {when.minute}
    set seconds of d to 0
    set newEvent to make new event with properties ¬
      {{summary:"{safe}", start date:d, end date:d, allday event:false}}
    tell newEvent
      make new display alarm at end with properties {{trigger interval:0}}
    end tell
  end tell
end tell'''
    if dry_run:
        print(f"  [dry-run] would add: {summary} @ {when:%d %b %Y %H:%M}")
        return
    osa(script)
    print(f"  added: {summary} @ {when:%d %b %Y %H:%M}")


def remove_event(calendar, summary, dry_run=False):
    safe = summary.replace('"', "'")
    if dry_run:
        print(f"  [dry-run] would remove: {summary}")
        return
    osa(f'''
tell application "Calendar"
  repeat with c in calendars
    if name of c is "{calendar}" then
      repeat with e in (every event of c whose summary is "{safe}")
        delete e
      end repeat
    end if
  end repeat
end tell''')
    print(f"  removed: {summary}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--calendar", default=DEFAULT_CALENDAR)
    ap.add_argument("--feed", default=FEED)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-prune", action="store_true",
                    help="don't remove events that left the feed (completed tasks)")
    args = ap.parse_args()

    wanted = parse_events(fetch_feed(args.feed))
    print(f"feed has {len(wanted)} event(s)")
    if not wanted:
        # never let a parse failure or an outage empty the calendar
        print("refusing to continue: feed returned no events", file=sys.stderr)
        return 1

    try:
        have = existing_events(args.calendar)
    except RuntimeError as e:
        print(f"could not read calendar {args.calendar!r}: {e}", file=sys.stderr)
        return 1
    print(f"calendar {args.calendar!r} has {len(have)} event(s)")

    wanted_names = {s for s, _ in wanted}
    for summary, when in wanted:
        if summary not in have:
            add_event(args.calendar, summary, when, args.dry_run)

    if not args.no_prune:
        # anything the feed dropped was completed or deleted in the app
        for stale in sorted(have - wanted_names):
            if stale.startswith("To do:"):
                remove_event(args.calendar, stale, args.dry_run)

    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env node
/* Checks the natural-language due-date reader:   node test-due-dates.js
 *
 * The parser is lifted straight out of index.html rather than copied here,
 * so the thing under test is always the thing that ships. "now" is pinned to
 * Thursday 5 November 2026, 10:00 local, which is what makes every expected
 * answer below a fixed string instead of a moving target.
 *
 * Half of these cases are tasks with NO date in them. Those matter most: a
 * reader that volunteers a due date for "buy 2 apples" is worse than no
 * reader at all, so each one is a test that nothing was detected.
 */
var fs = require("fs");
var path = require("path");

var src = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
var from = src.indexOf("// ── Natural-language due dates");
var to = src.indexOf("function ensureNotifyPermission()");
if (from < 0 || to < 0 || to < from) {
  console.error("Could not find the parser in index.html — markers moved?");
  process.exit(2);
}
var parseNaturalDue = new Function(
  src.slice(from, to) + "\nreturn parseNaturalDue;"
)();

var NOW = new Date(2026, 10, 5, 10, 0, 0, 0).getTime();   // Thu 5 Nov 2026
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function stamp(ts) {
  var d = new Date(ts);
  return DAYS[d.getDay()] + " " + d.getDate() + "/" + (d.getMonth() + 1) + " " +
    String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}

// [typed text, expected date or null, expected task text left behind]
var CASES = [
  ["call mum tomorrow 6pm",            "Fri 6/11 18:00",  "call mum"],
  ["call mum tomorrow at 6pm",         "Fri 6/11 18:00",  "call mum"],
  ["gym tonight",                      "Thu 5/11 20:00",  "gym"],
  ["dentist friday 9am",               "Fri 6/11 09:00",  "dentist"],
  ["dentist on friday",                "Fri 6/11 09:00",  "dentist"],
  ["file VAT return next friday 4pm",  "Fri 13/11 16:00", "file VAT return"],
  ["pay rent on the 1st of december",  "Tue 1/12 09:00",  "pay rent"],
  ["submit report by eod",             "Thu 5/11 18:00",  "submit report"],
  ["submit report end of week",        "Fri 6/11 09:00",  "submit report"],
  ["renew passport next month",        "Sat 5/12 09:00",  "renew passport"],
  ["book flights in 3 days",           "Sun 8/11 09:00",  "book flights"],
  ["take pizza out in 20 minutes",     "Thu 5/11 10:20",  "take pizza out"],
  ["call bank in 2 hours",             "Thu 5/11 12:00",  "call bank"],
  ["squash with hany sat 7pm",         "Sat 7/11 19:00",  "squash with hany"],
  ["squash with hany on sat",          "Sat 7/11 09:00",  "squash with hany"],
  ["meeting 6/11 18:00",               "Fri 6/11 18:00",  "meeting"],
  ["meeting nov 6 at 3",               "Fri 6/11 15:00",  "meeting"],
  ["meeting 6 nov 2027",               "Sat 6/11 09:00",  "meeting"],
  ["deadline 2026-12-24 23:00",        "Thu 24/12 23:00", "deadline"],
  ["check in with sarah tomorrow",     "Fri 6/11 09:00",  "check in with sarah"],
  ["lunch with ali thursday",          "Thu 5/11 13:00",  "lunch with ali"],
  ["dinner at 8",                      "Thu 5/11 20:00",  "dinner"],
  ["breakfast at 7",                   "Fri 6/11 07:00",  "breakfast"],
  ["flight 12/12 at 04:30",            "Sat 12/12 04:30", "flight"],
  ["gym at 6 in the morning",          "Fri 6/11 06:00",  "gym"],
  ["pick up kids at 2.30",             "Thu 5/11 14:30",  "pick up kids"],
  ["team sync tomorrow morning",       "Fri 6/11 09:00",  "team sync"],
  ["groceries this weekend",           "Sat 7/11 09:00",  "groceries"],
  ["6.11.2026 inspection",             "Fri 6/11 09:00",  "inspection"],
  ["finish deck before 15 nov",        "Sun 15/11 09:00", "finish deck"],
  ["midnight deadline",                "Thu 5/11 23:59",  "deadline"],
  ["thursday 6pm",                     "Thu 5/11 18:00",  "thursday 6pm"],
  ["thursday 10am",                    "Thu 12/11 10:00", "thursday 10am"],

  // Nothing here is a date, and the reader has to leave all of it alone.
  ["buy 2 apples",                     null, null],
  ["read chapter 4",                   null, null],
  ["order 3 shirts",                   null, null],
  ["iphone 15 pro case",               null, null],
  ["fix bug 2.1.4",                    null, null],
  ["send invoice #105",                null, null],
  ["version 1.5 release notes",        null, null],
  ["call 0100 1234567",                null, null],
  ["pay 50% deposit",                  null, null],
  ["book table for 4",                 null, null],
  ["i sat down and read",              null, null],
  ["walk in the sun",                  null, null],
  ["sun cream",                        null, null],
  ["20 push ups",                      null, null],
  ["review PR 123",                    null, null],
  ["standup every monday",             null, null],   // no recurring tasks here
  ["email john",                       null, null]
];

var failed = 0;
CASES.forEach(function (c) {
  var r = parseNaturalDue(c[0], NOW);
  var got = r ? stamp(r.due) : null;
  var ok = (got === c[1]) && (!r || !c[2] || r.text === c[2]);
  if (!ok) {
    failed++;
    console.log("FAIL  " + JSON.stringify(c[0]));
    console.log("      expected " + (c[1] || "no date") + (c[2] ? '  "' + c[2] + '"' : ""));
    console.log("      got      " + (got || "no date") + (r ? '  "' + r.text + '"' : ""));
  }
});

console.log((CASES.length - failed) + "/" + CASES.length + " passed");
process.exit(failed ? 1 : 0);

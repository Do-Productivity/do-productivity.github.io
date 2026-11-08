#!/usr/bin/env node
/* Checks the natural-language due-date reader and the repeat arithmetic:
 *
 *     node test-due-dates.js
 *
 * Both are lifted straight out of index.html rather than copied here, so the
 * thing under test is always the thing that ships. "now" is pinned to
 * Thursday 5 November 2026, 10:00 local, which is what makes every expected
 * answer below a fixed string instead of a moving target.
 *
 * Half of the reader's cases are tasks with NO date in them. Those matter
 * most: a reader that volunteers a due date for "buy 2 apples" is worse than
 * no reader at all, so each one is a test that nothing was detected.
 */
var fs = require("fs");
var path = require("path");

var src = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

function slice(fromMarker, toMarker, what) {
  var a = src.indexOf(fromMarker), b = src.indexOf(toMarker);
  if (a < 0 || b < 0 || b < a) {
    console.error("Could not find " + what + " in index.html — markers moved?");
    process.exit(2);
  }
  return src.slice(a, b);
}

// The reader calls defaultDue, which lives with the repeat model, so both
// blocks are evaluated together in one scope.
var sandbox = new Function(
  slice("// ── Repeating tasks", "function normalizeTasks(", "the repeat model") +
  slice("// ── Natural-language due dates", "function ensureNotifyPermission()", "the date reader") +
  "\nreturn { parseNaturalDue: parseNaturalDue, repLabel: repLabel," +
  "         nextOccurrence: nextOccurrence, defaultDue: defaultDue };"
)();
var parseNaturalDue = sandbox.parseNaturalDue;
var repLabel = sandbox.repLabel;
var nextOccurrence = sandbox.nextOccurrence;
function label(r) { return repLabel(r); }

var NOW = new Date(2026, 10, 5, 10, 0, 0, 0).getTime();   // Thu 5 Nov 2026
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function stamp(ts) {
  var d = new Date(ts);
  return DAYS[d.getDay()] + " " + d.getDate() + "/" + (d.getMonth() + 1) + " " +
    String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}

// [typed text, expected date or null, expected task text left behind,
//  expected repeat rule or undefined]
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
  // Repeats. "every X" is two statements — how often, and when the first
  // one falls — so the date must survive having the repeat taken out.
  ["standup every monday",             "Mon 9/11 09:00",  "standup",   "every week"],
  ["team sync every monday 10am",      "Mon 9/11 10:00",  "team sync", "every week"],
  ["gym every other monday",           "Mon 9/11 09:00",  "gym",       "every other week"],
  ["pay rent every month",             "Thu 5/11 11:00",  "pay rent",  "every month"],
  ["standup daily at 9",               "Fri 6/11 09:00",  "standup",   "every day"],
  ["water plants every 3 days",        "Thu 5/11 11:00",  "water plants", "every 3 days"],
  ["payroll every weekday",            "Thu 5/11 11:00",  "payroll",   "every weekday"],
  ["renew domain yearly",              "Thu 5/11 11:00",  "renew domain", "every year"],
  ["reconcile quarterly",              "Thu 5/11 11:00",  "reconcile", "every 3 months"],
  // and one it cannot express, which must claim nothing at all
  ["review every 2nd tuesday of the month", null, null],
  ["email john",                       null, null]
];

var failed = 0;
CASES.forEach(function (c) {
  var r = parseNaturalDue(c[0], NOW);
  var got = r ? stamp(r.due) : null;
  var gotRep = (r && r.rep) ? label(r.rep) : undefined;
  var ok = (got === c[1]) && (!r || !c[2] || r.text === c[2]) && gotRep === c[3];
  if (!ok) {
    failed++;
    console.log("FAIL  " + JSON.stringify(c[0]));
    console.log("      expected " + (c[1] || "no date") + (c[2] ? '  "' + c[2] + '"' : "") +
      (c[3] ? "  [" + c[3] + "]" : ""));
    console.log("      got      " + (got || "no date") + (r ? '  "' + r.text + '"' : "") +
      (gotRep ? "  [" + gotRep + "]" : ""));
  }
});

// ── repeat arithmetic ────────────────────────────────────────────────
// The reader only decides what the rule IS. This is the part that decides
// when the next one falls, and it is where a repeat quietly rots: a monthly
// task walking backwards a day each short month, or a weekday rule landing
// on a Saturday.

function at(y, m, d, h, min) { return new Date(y, m - 1, d, h || 9, min || 0, 0, 0).getTime(); }

var REPEATS = [
  // [label, from, rule, now, expected next]
  ["daily",
   at(2026, 11, 5), { unit: "day", n: 1 }, at(2026, 11, 5, 10), at(2026, 11, 6)],
  ["every 3 days",
   at(2026, 11, 5), { unit: "day", n: 3 }, at(2026, 11, 5, 10), at(2026, 11, 8)],
  ["weekly keeps its weekday",
   at(2026, 11, 5), { unit: "week", n: 1 }, at(2026, 11, 5, 10), at(2026, 11, 12)],
  ["fortnightly",
   at(2026, 11, 5), { unit: "week", n: 2 }, at(2026, 11, 5, 10), at(2026, 11, 19)],
  ["weekly ticked three weeks late still lands on a Thursday",
   at(2026, 11, 5), { unit: "week", n: 1 }, at(2026, 11, 24, 10), at(2026, 11, 26)],
  ["monthly",
   at(2026, 11, 5), { unit: "month", n: 1, day: 5 }, at(2026, 11, 5, 10), at(2026, 12, 5)],
  ["the 31st becomes the 30th in a short month",
   at(2026, 10, 31), { unit: "month", n: 1, day: 31 }, at(2026, 10, 31, 10), at(2026, 11, 30)],
  ["and comes BACK to the 31st the month after",
   at(2026, 11, 30), { unit: "month", n: 1, day: 31 }, at(2026, 11, 30, 10), at(2026, 12, 31)],
  ["the 31st in January lands on the 28th of February",
   at(2027, 1, 31), { unit: "month", n: 1, day: 31 }, at(2027, 1, 31, 10), at(2027, 2, 28)],
  ["quarterly",
   at(2026, 11, 5), { unit: "month", n: 3, day: 5 }, at(2026, 11, 5, 10), at(2027, 2, 5)],
  ["yearly",
   at(2026, 11, 5), { unit: "year", n: 1, day: 5 }, at(2026, 11, 5, 10), at(2027, 11, 5)],
  ["a weekday rule skips Saturday and Sunday",
   at(2026, 11, 6), { unit: "weekday" }, at(2026, 11, 6, 10), at(2026, 11, 9)],
  ["and steps one day midweek",
   at(2026, 11, 9), { unit: "weekday" }, at(2026, 11, 9, 10), at(2026, 11, 10)],
  ["a daily task months overdue jumps to tomorrow, not to the day after it was set",
   at(2026, 8, 1), { unit: "day", n: 1 }, at(2026, 11, 5, 10), at(2026, 11, 6)],
  ["the time of day is kept",
   at(2026, 11, 5, 18, 30), { unit: "week", n: 1 }, at(2026, 11, 5, 19), at(2026, 11, 12, 18, 30)]
];

REPEATS.forEach(function (c) {
  var got = nextOccurrence(c[1], c[2], c[3]);
  if (got !== c[4]) {
    failed++;
    console.log("FAIL  repeat: " + c[0]);
    console.log("      expected " + new Date(c[4]).toString().slice(0, 24));
    console.log("      got      " + new Date(got).toString().slice(0, 24));
  }
});

var total = CASES.length + REPEATS.length;
console.log((total - failed) + "/" + total + " passed  (" +
  CASES.length + " reading, " + REPEATS.length + " repeat arithmetic)");
process.exit(failed ? 1 : 0);

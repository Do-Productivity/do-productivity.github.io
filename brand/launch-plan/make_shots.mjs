#!/usr/bin/env node
/* Screenshots for the launch plan, with invented data.
 *
 *   npm i -D playwright && npx playwright install chromium   (once)
 *   node brand/launch-plan/make_shots.mjs
 *
 * Every task, meeting and name below is made up. None of it is Miha's, and
 * none of it should ever be: these pictures end up in a PDF that goes to
 * other people, and a real calendar in a marketing document is a leak.
 *
 * The cast is deliberately mixed — a parent with a school run, a couple with
 * an anniversary, someone single with a flat viewing, work that belongs to
 * nobody in particular — because the plan sells the app to men and women,
 * single people and families, and a screenshot full of one kind of life
 * quietly tells everyone else it is not for them.
 *
 * Sizes are the real ones: a Mac window, the folding phone shut, the folding
 * phone open. They are measured, not chosen to flatter.
 */
import { chromium } from "playwright";
import path from "path";
import { fileURLToPath } from "url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const IMG = path.join(HERE, "img");
const APP = "file://" + path.join(ROOT, "index.html");

// ── the invented day ──────────────────────────────────────────────────────

const PERSONAL = [
  { text: "Pick Nour up from swimming", at: [17, 30] },
  { text: "Book the dentist for Mum" },
  { text: "Anniversary dinner — reserve a table", in_days: 3 },
  { text: "Flat viewing, Zamalek", in_days: 1, at: [12, 0] },
  { text: "Renew the gym membership" },
];

const BUSINESS = [
  { text: "Send Q4 budget to Layla", at: [16, 0] },
  { text: "Review the Hassan & Co contract", in_days: 1 },
  { text: "Board deck — first pass", in_days: 2 },
  { text: "Reply to the Nile Trading brief" },
];

const EVENTS = [
  { t: "Team standup", a: [9, 0], b: [10, 0] },
  { t: "Design review", a: [10, 30], b: [11, 30], w: "Studio" },
  { t: "Lunch with Sara", a: [13, 0], b: [14, 0], w: "Zooba" },
  { t: "Client call — Nile Co", a: [15, 0], b: [15, 45] },
  { t: "Parents' evening", a: [18, 30], b: [19, 30], w: "Nour's school" },
];

// Tomorrow and the day after, so the week strip has a shape to show.
const EVENTS_1 = [
  { t: "One-to-one, Omar", a: [11, 0], b: [11, 30] },
  { t: "Dentist", a: [14, 0], b: [14, 45] },
];
const EVENTS_2 = [
  { t: "Quarterly review", a: [10, 0], b: [12, 0] },
  { t: "Anniversary dinner", a: [20, 0], b: [22, 0], w: "Sachi" },
];

const seed = `(${function (P, B, E0, E1, E2) {
  function at(dayOffset, hm) {
    var d = new Date();
    d.setDate(d.getDate() + dayOffset);
    d.setHours(hm[0], hm[1], 0, 0);
    return d.getTime();
  }
  function key(ts) {
    var d = new Date(ts);
    return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) +
           "-" + ("0" + d.getDate()).slice(-2);
  }
  function tasks(src) {
    return src.map(function (t, i) {
      var o = { text: t.text, done: false, id: "demo" + i + Math.random().toString(36).slice(2, 6), mt: Date.now() };
      if (t.at || t.in_days) o.due = at(t.in_days || 0, t.at || [9, 0]);
      return o;
    });
  }
  function events(dayOffset, src) {
    return src.map(function (e, i) {
      return {
        id: "demoev" + dayOffset + "-" + i,
        subject: e.t,
        start: at(dayOffset, e.a),
        end: at(dayOffset, e.b),
        allDay: false,
        where: e.w || "",
      };
    });
  }
  var NOTES = [
    "Flat viewing — ask about the service charge and the parking space.",
    "Budget: Layla wants the headcount split out by team, not by cost centre.",
  ];
  var RUNS = [
    { name: "Board deck — first pass", steps: ["Pull Q4 numbers", "Draft the three slides that matter", "Send to Omar for a read"] },
  ];
  try {
    localStorage.clear();
    localStorage.setItem("dia_todo_personal_v1", JSON.stringify(tasks(P)));
    localStorage.setItem("dia_todo_business_v1", JSON.stringify(tasks(B)));
    var days = {}, atMap = {}, now = Date.now();
    [[0, E0], [1, E1], [2, E2]].forEach(function (pair) {
      var evs = events(pair[0], pair[1]);
      var k = key(at(pair[0], [12, 0]));
      days[k] = evs;
      atMap[k] = now;
    });
    localStorage.setItem("dia_todo_msevents_v1", JSON.stringify({ days: days, at: atMap }));
    // A subscribed calendar, so the picture shows the app with one connected
    // rather than the prompt asking you to connect one. Nothing is fetched:
    // the cache above is stamped now, so it is never stale enough to refresh.
    localStorage.setItem("dia_todo_nldue_tip", "1");
    localStorage.setItem("dia_todo_notes_v1", JSON.stringify(
      NOTES.map(function (t, i) { return { text: t, id: "demon" + i, created: Date.now() - i * 3600000 }; })));
    localStorage.setItem("dia_todo_runs_v1", JSON.stringify(
      RUNS.map(function (r, i) {
        return {
          id: "demor" + i, name: r.name, mt: Date.now(),
          dueAt: at(2, [9, 0]),
          steps: r.steps.map(function (st, j) { return { id: "demos" + i + j, text: st }; }),
        };
      })));
    localStorage.setItem("dia_todo_icsfeeds_v1", JSON.stringify([
      { id: "fdemo", url: "https://example.com/work.ics", name: "Work" }
    ]));
  } catch (e) { /* a screenshot run is not worth throwing over */ }
}})(${JSON.stringify(PERSONAL)}, ${JSON.stringify(BUSINESS)}, ${JSON.stringify(EVENTS)}, ${JSON.stringify(EVENTS_1)}, ${JSON.stringify(EVENTS_2)});`;

// ── the shots ─────────────────────────────────────────────────────────────
//
// name, viewport, and what to do once the app has settled.

const SHOTS = [
  { name: "mac-lists.png",         w: 1440, h: 900, act: "lists" },
  { name: "mac-calendar.png",      w: 1440, h: 900, act: "calendar" },
  { name: "iphone-calendar.png",   w: 393,  h: 852, act: "calendar" },
  { name: "iphone-lists.png",      w: 393,  h: 852, act: "lists" },
  { name: "folded-calendar.png",   w: 373,  h: 603, act: "calendar" },
  { name: "unfolded-calendar.png", w: 1114, h: 594, act: "calendar" },
  // The three the first draft used, retaken on the current build with the
  // same invented day, so the whole document is one dataset.
  { name: "folded-lists.png",      w: 373,  h: 603, act: "lists" },
  { name: "unfolded-867.png",      w: 867,  h: 594, act: "lists" },
  { name: "unfolded-1114.png",     w: 1114, h: 594, act: "lists" },
];

async function run() {
  const browser = await chromium.launch();
  for (const s of SHOTS) {
    const ctx = await browser.newContext({
      viewport: { width: s.w, height: s.h },
      deviceScaleFactor: 2,
    });
    await ctx.addInitScript(seed);
    const page = await ctx.newPage();
    // Nine in the morning, every time this is run. Without it the pictures
    // depend on the hour they were taken: run it after six and half the
    // demo day is marked overdue in red, which is not what the app is for.
    const nine = new Date();
    nine.setHours(8, 40, 0, 0);
    await page.clock.setFixedTime(nine);
    await page.goto(APP, { waitUntil: "load" });
    await page.waitForTimeout(1200);

    if (s.act === "calendar") {
      // On a wide window the calendar is a column you switch on; on a narrow
      // one it is a card in the fan. Try the button, then fall back to
      // bringing the panel itself into view.
      const btn = await page.$("#cal-btn");
      const visible = btn && (await btn.isVisible());
      if (visible) {
        const on = await page.$(".panel.cal");
        if (!on || !(await on.isVisible())) await btn.click();
      } else {
        // Narrow: the calendar is the fifth card in the fan, not one of the
        // four tabs, so it is reached by tapping its card — which is also
        // how a person reaches it.
        await page.evaluate(() => {
          const cards = Array.from(document.querySelectorAll(".fan-card"));
          const c = cards.find((b) => /^calendar/i.test((b.textContent || "").trim()));
          if (c) c.click();
        });
      }
      await page.waitForTimeout(900);
      // The day opens scrolled to the current hour, which by the evening
      // hides the morning. A picture of the product should be the whole day.
      await page.evaluate(() => {
        const sc = document.querySelector(".cal-scroll");
        if (!sc) return;
        // Start at the first thing in the day rather than at midnight: the
        // quiet hours are already thin, but on a short screen even thin
        // ones push the actual day off the bottom.
        const first = sc.querySelector(".cal-item");
        sc.scrollTop = first ? Math.max(0, first.offsetTop - 28) : 0;
      });
      await page.waitForTimeout(350);
    }

    await page.screenshot({ path: path.join(IMG, s.name) });
    console.log("  " + s.name + "  " + s.w + "x" + s.h);
    await ctx.close();
  }
  await browser.close();
}

run().catch((e) => { console.error(e); process.exit(1); });

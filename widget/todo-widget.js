// ─────────────────────────────────────────────────────────────
//  My To Do List — iOS home screen widget
//  Runs in Scriptable (free on the App Store).
//  Reads the same live list the web app syncs to, so the widget
//  always matches what you see on the phone and the Mac.
//  Works in small / medium / large sizes.
// ─────────────────────────────────────────────────────────────

const FEED = "https://gist.githubusercontent.com/ahmedmohsen18/" +
  "1f3e9c2d3186c395b62391c6b62f0358/raw/dia-todo.json";
const APP_URL = "https://ahmedmohsen18.github.io/my-todo-list/";

// paper palette, matching the web app
const PAPER  = new Color("#f7f3e9");
const CARD   = new Color("#fffdf7");
const INK    = new Color("#2b2620");
const SOFT   = new Color("#6b6259");
const FAINT  = new Color("#a89f93");
const RED    = new Color("#c8553d");   // Personal
const BLUE   = new Color("#3d6b8c");   // Business
const AMBER  = new Color("#b3701f");   // due today

const size = config.runsInWidget ? config.widgetFamily : "medium";
const ROWS = { small: 3, medium: 4, large: 9 }[size] || 4;

// ── data ─────────────────────────────────────────────────────

async function loadLists() {
  const cache = FileManager.local();
  const cachePath = cache.joinPath(cache.cacheDirectory(), "todo-widget.json");
  try {
    const req = new Request(FEED);
    req.timeoutInterval = 15;
    const doc = await req.loadJSON();
    if (doc && doc.lists) {
      cache.writeString(cachePath, JSON.stringify(doc));
      return doc;
    }
    throw new Error("bad payload");
  } catch (e) {
    // offline — fall back to the last good copy so the widget never goes blank
    if (cache.fileExists(cachePath)) {
      try { return JSON.parse(cache.readString(cachePath)); } catch (_) {}
    }
    return null;
  }
}

function collectTasks(doc) {
  const out = [];
  for (const [key, label, tint] of [["personal", "Personal", RED],
                                    ["business", "Business", BLUE]]) {
    for (const t of (doc.lists[key] || [])) {
      if (t.done || t.deleted) continue;
      out.push({ text: t.text, due: t.due || null, label, tint });
    }
  }
  // dated first, soonest at the top; undated afterwards
  out.sort((a, b) => {
    if (a.due && b.due) return a.due - b.due;
    if (a.due) return -1;
    if (b.due) return 1;
    return 0;
  });
  return out;
}

// ── formatting ───────────────────────────────────────────────

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() &&
         a.getMonth() === b.getMonth() &&
         a.getDate() === b.getDate();
}

function dueLabel(ts) {
  if (!ts) return { text: "", color: FAINT };
  const now = new Date();
  const d = new Date(ts);
  const hhmm = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

  if (d < now) return { text: "Overdue", color: RED };
  if (sameDay(d, now)) return { text: hhmm, color: AMBER };

  const tomorrow = new Date(now.getTime() + 86400000);
  if (sameDay(d, tomorrow)) return { text: "Tomorrow", color: SOFT };

  const days = Math.ceil((d - now) / 86400000);
  if (days <= 6) {
    return { text: d.toLocaleDateString([], { weekday: "short" }), color: SOFT };
  }
  return {
    text: d.toLocaleDateString([], { day: "numeric", month: "short" }),
    color: SOFT
  };
}

// ── widget ───────────────────────────────────────────────────

function buildWidget(doc) {
  const w = new ListWidget();
  w.backgroundColor = PAPER;
  w.setPadding(14, 14, 12, 14);
  w.url = APP_URL;                     // tap the widget → opens the app
  // ask iOS to refresh in ~15 minutes (it decides the real cadence)
  w.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000);

  if (!doc) {
    const t = w.addText("Can't reach your list");
    t.textColor = SOFT;
    t.font = Font.systemFont(13);
    return w;
  }

  const tasks = collectTasks(doc);
  const personal = tasks.filter(t => t.label === "Personal").length;
  const business = tasks.length - personal;

  // header ----------------------------------------------------
  const head = w.addStack();
  head.centerAlignContent();

  const title = head.addText("My To Do List");
  title.textColor = INK;
  title.font = Font.semiboldSystemFont(size === "small" ? 12 : 13);

  head.addSpacer();

  const count = head.addText(String(tasks.length));
  count.textColor = FAINT;
  count.font = Font.semiboldSystemFont(size === "small" ? 12 : 13);

  // hairline rule
  const rule = w.addStack();
  rule.backgroundColor = new Color("#d9d2c2");
  rule.size = new Size(0, 1);
  rule.addSpacer();
  w.addSpacer(8);

  // rows ------------------------------------------------------
  if (tasks.length === 0) {
    const t = w.addText("All clear 🎉");
    t.textColor = SOFT;
    t.font = Font.systemFont(13);
  }

  const shown = tasks.slice(0, ROWS);
  for (let i = 0; i < shown.length; i++) {
    const task = shown[i];
    const row = w.addStack();
    row.centerAlignContent();

    // coloured bar showing which list it belongs to
    const bar = row.addStack();
    bar.backgroundColor = task.tint;
    bar.size = new Size(2.5, size === "small" ? 12 : 14);
    bar.cornerRadius = 1.5;
    bar.addSpacer();
    row.addSpacer(7);

    const label = row.addText(task.text);
    label.textColor = INK;
    label.font = Font.systemFont(size === "small" ? 11 : 12.5);
    label.lineLimit = 1;
    label.minimumScaleFactor = 0.85;

    row.addSpacer(6);

    const due = dueLabel(task.due);
    if (due.text) {
      const d = row.addText(due.text);
      d.textColor = due.color;
      d.font = Font.mediumSystemFont(size === "small" ? 10 : 11);
      d.lineLimit = 1;
    }

    if (i < shown.length - 1) w.addSpacer(size === "small" ? 5 : 7);
  }

  // footer ----------------------------------------------------
  if (size !== "small") {
    w.addSpacer();
    const foot = w.addStack();
    foot.centerAlignContent();

    const extra = tasks.length - shown.length;
    const left = foot.addText(
      extra > 0 ? `+${extra} more` : `${personal} personal · ${business} business`
    );
    left.textColor = FAINT;
    left.font = Font.systemFont(10);

    foot.addSpacer();

    const stamp = foot.addText(
      new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
    );
    stamp.textColor = FAINT;
    stamp.font = Font.systemFont(10);
  } else {
    w.addSpacer();
  }

  return w;
}

// ── run ──────────────────────────────────────────────────────

const doc = await loadLists();
const widget = buildWidget(doc);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  // tapping Run inside Scriptable previews it
  await widget.presentMedium();
}
Script.complete();

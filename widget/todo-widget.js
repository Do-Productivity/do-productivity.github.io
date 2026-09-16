// ─────────────────────────────────────────────────────────────
//  My To Do List — iOS home screen widget  (Scriptable)
//
//  Mirrors the app's dashboard: a titled card per list, with the
//  same circles, colours and due labels.
//
//  WIDGET PARAMETER (long-press widget → Edit Widget → Parameter):
//     personal   → the Personal card only
//     business   → the Business card only
//     (blank)    → both lists together
// ─────────────────────────────────────────────────────────────

const FEED = "https://gist.githubusercontent.com/ahmedmohsen18/" +
  "1f3e9c2d3186c395b62391c6b62f0358/raw/dia-todo.json";
const APP_URL = "https://ahmedmohsen18.github.io/my-todo-list/";

// paper palette, matching the web app
const PAPER = new Color("#f7f3e9");
const INK   = new Color("#2b2620");
const SOFT  = new Color("#6b6259");
const FAINT = new Color("#a89f93");
const RULE  = new Color("#d9d2c2");
const RED   = new Color("#c8553d");   // Personal
const BLUE  = new Color("#3d6b8c");   // Business
const AMBER = new Color("#b3701f");   // due today

const LISTS = {
  personal: { key: "personal", title: "Personal", sub: "LIFE & HOME",      tint: RED  },
  business: { key: "business", title: "Business", sub: "WORK & PROJECTS",  tint: BLUE }
};

const size  = config.runsInWidget ? config.widgetFamily : "medium";
const param = (args.widgetParameter || "").trim().toLowerCase();
const which = LISTS[param] ? [LISTS[param]] : [LISTS.personal, LISTS.business];
const bothLists = which.length === 2;

// how many rows fit
const ROWS = bothLists
  ? ({ small: 2, medium: 3, large: 6 }[size] || 3)      // per list
  : ({ small: 3, medium: 5, large: 12 }[size] || 5);

// ── data ─────────────────────────────────────────────────────

async function loadDoc() {
  const fm = FileManager.local();
  const cachePath = fm.joinPath(fm.cacheDirectory(), "todo-widget.json");
  try {
    // The raw gist URL is cached for 5 minutes and iOS caches on top of that,
    // so bust both — otherwise the widget shows a stale list.
    const req = new Request(FEED + "?t=" + Date.now());
    req.headers = { "Cache-Control": "no-cache", "Pragma": "no-cache" };
    req.timeoutInterval = 15;
    const doc = await req.loadJSON();
    if (doc && doc.lists) {
      fm.writeString(cachePath, JSON.stringify(doc));
      return { doc, live: true };
    }
    throw new Error("bad payload");
  } catch (e) {
    if (fm.fileExists(cachePath)) {
      try { return { doc: JSON.parse(fm.readString(cachePath)), live: false }; }
      catch (_) {}
    }
    return { doc: null, live: false };
  }
}

function activeTasks(doc, key) {
  const out = (doc.lists[key] || []).filter(t => !t.done && !t.deleted);
  out.sort((a, b) => {
    if (a.due && b.due) return a.due - b.due;
    if (a.due) return -1;
    if (b.due) return 1;
    return 0;
  });
  return out;
}

// ── formatting ───────────────────────────────────────────────

const sameDay = (a, b) =>
  a.getFullYear() === b.getFullYear() &&
  a.getMonth() === b.getMonth() &&
  a.getDate() === b.getDate();

function dueLabel(ts) {
  if (!ts) return null;
  const now = new Date(), d = new Date(ts);
  if (d < now) return { text: "Overdue", color: RED, bold: true };
  if (sameDay(d, now)) {
    return {
      text: d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
      color: AMBER, bold: true
    };
  }
  if (sameDay(d, new Date(now.getTime() + 86400000))) {
    return { text: "Tomorrow", color: SOFT, bold: false };
  }
  const days = Math.ceil((d - now) / 86400000);
  if (days <= 6) {
    return { text: d.toLocaleDateString([], { weekday: "short" }), color: SOFT, bold: false };
  }
  return {
    text: d.toLocaleDateString([], { day: "numeric", month: "short" }),
    color: SOFT, bold: false
  };
}

function serif(sizePt, bold) {
  // matches the app's serif headings; falls back to system if unavailable
  return new Font(bold ? "Georgia-Bold" : "Georgia", sizePt);
}

// ── drawing ──────────────────────────────────────────────────

function hairline(container) {
  const line = container.addStack();
  line.backgroundColor = RULE;
  line.size = new Size(0, 1);
  line.addSpacer();
}

function drawCard(container, list, tasks, compact) {
  // heading: "Personal." with the coloured full stop, like the app
  const head = container.addStack();
  head.bottomAlignContent();

  const t = head.addText(list.title);
  t.textColor = INK;
  t.font = serif(compact ? 14 : 17, true);

  const dot = head.addText(".");
  dot.textColor = list.tint;
  dot.font = serif(compact ? 14 : 17, true);

  head.addSpacer();

  const n = head.addText(String(tasks.length));
  n.textColor = FAINT;
  n.font = Font.semiboldSystemFont(compact ? 10 : 12);

  if (!compact) {
    const sub = container.addText(list.sub);
    sub.textColor = FAINT;
    sub.font = Font.semiboldSystemFont(8);
  }

  container.addSpacer(5);
  hairline(container);
  container.addSpacer(6);

  if (tasks.length === 0) {
    const e = container.addText("Nothing here yet.");
    e.textColor = FAINT;
    e.font = Font.italicSystemFont(compact ? 10 : 11);
    return;
  }

  const shown = tasks.slice(0, ROWS);
  for (let i = 0; i < shown.length; i++) {
    const task = shown[i];
    const row = container.addStack();
    row.centerAlignContent();

    // open circle, as on the dashboard
    const circle = row.addText("○");
    circle.textColor = list.tint;
    circle.font = Font.systemFont(compact ? 10 : 12);
    row.addSpacer(5);

    const label = row.addText(task.text);
    label.textColor = INK;
    label.font = Font.systemFont(compact ? 10.5 : 12);
    label.lineLimit = 1;
    label.minimumScaleFactor = 0.8;

    row.addSpacer(4);

    const due = dueLabel(task.due);
    if (due) {
      const d = row.addText(due.text);
      d.textColor = due.color;
      d.font = due.bold
        ? Font.semiboldSystemFont(compact ? 9 : 10)
        : Font.systemFont(compact ? 9 : 10);
      d.lineLimit = 1;
    }

    if (i < shown.length - 1) container.addSpacer(compact ? 4 : 6);
  }

  const extra = tasks.length - shown.length;
  if (extra > 0) {
    container.addSpacer(4);
    const more = container.addText(`+${extra} more`);
    more.textColor = FAINT;
    more.font = Font.systemFont(compact ? 8.5 : 9.5);
  }
}

// ── widget ───────────────────────────────────────────────────

function build({ doc, live }) {
  const w = new ListWidget();
  w.backgroundColor = PAPER;
  w.setPadding(12, 13, 10, 13);
  w.url = APP_URL;
  w.refreshAfterDate = new Date(Date.now() + 10 * 60 * 1000);

  if (!doc) {
    const t = w.addText("Can't reach your list");
    t.textColor = SOFT;
    t.font = Font.systemFont(12);
    return w;
  }

  if (bothLists) {
    // two columns side by side, like the desktop dashboard
    const cols = w.addStack();
    cols.layoutHorizontally();
    cols.topAlignContent();

    which.forEach((list, idx) => {
      const col = cols.addStack();
      col.layoutVertically();
      drawCard(col, list, activeTasks(doc, list.key), true);
      if (idx === 0) {
        cols.addSpacer(10);
        const sep = cols.addStack();
        sep.backgroundColor = RULE;
        sep.size = new Size(1, 0);
        sep.addSpacer();
        cols.addSpacer(10);
      }
    });
  } else {
    const col = w.addStack();
    col.layoutVertically();
    drawCard(col, which[0], activeTasks(doc, which[0].key), false);
  }

  // footer: freshness, so a stale widget is obvious
  w.addSpacer();
  const foot = w.addStack();
  foot.centerAlignContent();
  const stamp = foot.addText(
    (live ? "Updated " : "Offline · ") +
    new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
  );
  stamp.textColor = FAINT;
  stamp.font = Font.systemFont(8.5);
  foot.addSpacer();

  return w;
}

// ── run ──────────────────────────────────────────────────────

const result = await loadDoc();
const widget = build(result);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else if (size === "small") {
  await widget.presentSmall();
} else if (size === "large") {
  await widget.presentLarge();
} else {
  await widget.presentMedium();
}
Script.complete();

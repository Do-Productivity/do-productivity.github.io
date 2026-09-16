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

// Type scale per widget size. A large widget is roughly 2.5x the height of a
// medium one, so it needs genuinely larger type — not medium's sizes stretched.
const SCALE = {
  small:  { title: 15, sub: 8,  text: 11.5, due: 10,   circle: 11, gap: 5,  foot: 9,
            rows: { both: 3, one: 5 } },
  medium: { title: 19, sub: 9,  text: 14,   due: 11.5, circle: 13, gap: 7,  foot: 10,
            rows: { both: 4, one: 6 } },
  large:  { title: 27, sub: 12, text: 19,   due: 15,   circle: 18, gap: 13, foot: 12,
            rows: { both: 9, one: 15 } }
};
const S = Object.assign({}, SCALE[size] || SCALE.medium);

// two cards side by side get slightly tighter type so the text still fits
if (bothLists) {
  const k = size === "large" ? 0.82 : 0.86;
  for (const f of ["title", "sub", "text", "due", "circle"]) S[f] = S[f] * k;
  S.gap = S.gap * 0.85;
}
const ROWS = bothLists ? S.rows.both : S.rows.one;

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

function drawCard(container, list, tasks, showSub) {
  // heading: "Personal." with the coloured full stop, like the app
  const head = container.addStack();
  head.bottomAlignContent();

  const t = head.addText(list.title);
  t.textColor = INK;
  t.font = serif(S.title, true);

  const dot = head.addText(".");
  dot.textColor = list.tint;
  dot.font = serif(S.title, true);

  head.addSpacer();

  const n = head.addText(String(tasks.length));
  n.textColor = FAINT;
  n.font = Font.semiboldSystemFont(S.sub + 3);

  if (showSub) {
    const sub = container.addText(list.sub);
    sub.textColor = FAINT;
    sub.font = Font.semiboldSystemFont(S.sub);
  }

  container.addSpacer(S.gap * 0.7);
  hairline(container);
  container.addSpacer(S.gap);

  if (tasks.length === 0) {
    const e = container.addText("Nothing here yet.");
    e.textColor = FAINT;
    e.font = Font.italicSystemFont(S.text * 0.9);
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
    circle.font = Font.systemFont(S.circle);
    row.addSpacer(S.circle * 0.45);

    const label = row.addText(task.text);
    label.textColor = INK;
    label.font = Font.systemFont(S.text);
    label.lineLimit = 1;
    label.minimumScaleFactor = 0.8;

    row.addSpacer(4);

    const due = dueLabel(task.due);
    if (due) {
      const d = row.addText(due.text);
      d.textColor = due.color;
      d.font = due.bold
        ? Font.semiboldSystemFont(S.due)
        : Font.systemFont(S.due);
      d.lineLimit = 1;
    }

    if (i < shown.length - 1) container.addSpacer(S.gap);
  }

  const extra = tasks.length - shown.length;
  if (extra > 0) {
    container.addSpacer(4);
    const more = container.addText(`+${extra} more`);
    more.textColor = FAINT;
    more.font = Font.systemFont(S.due);
  }
}

// ── widget ───────────────────────────────────────────────────

function build({ doc, live }) {
  const w = new ListWidget();
  w.backgroundColor = PAPER;
  const pad = size === "large" ? 18 : size === "small" ? 10 : 13;
  w.setPadding(pad, pad, pad * 0.8, pad);
  w.url = APP_URL;
  // iOS decides the real cadence from a limited daily budget; this is only a
  // hint. Asking for 2 minutes gets us refreshed as often as the system will
  // allow (realistically every 5-15 min), rather than capping ourselves at 10.
  w.refreshAfterDate = new Date(Date.now() + 2 * 60 * 1000);

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
      drawCard(col, list, activeTasks(doc, list.key), size === "large");
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
    drawCard(col, which[0], activeTasks(doc, which[0].key), true);
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
  stamp.font = Font.systemFont(S.foot);
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

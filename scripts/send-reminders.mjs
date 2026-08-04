// Runs on a GitHub Actions schedule. Reads the sync gist, finds tasks whose
// due time has passed since the last run, and sends a Web Push notification
// to every subscribed device. State lives in the gist alongside the tasks.
import webpush from "web-push";

const { GIST_TOKEN, GIST_ID, VAPID_PRIVATE_KEY } = process.env;
const VAPID_PUBLIC_KEY = "BJUYqeW4BwJljjm3uodpK1Vdq9nPl8qiQNDrqMUKwDsJ8RFQw3rhlNddzd5XtFv8ZWQxWGF7RkhxE48hha6962o";
const DUE_LOOKBACK_MS = 24 * 3600 * 1000; // never notify for things >1 day stale
const STATE_PRUNE_MS = 7 * 24 * 3600 * 1000;

if (!GIST_TOKEN || !GIST_ID || !VAPID_PRIVATE_KEY) {
  console.error("missing env (GIST_TOKEN / GIST_ID / VAPID_PRIVATE_KEY)");
  process.exit(1);
}

const api = (path, opts = {}) =>
  fetch("https://api.github.com" + path, {
    ...opts,
    headers: {
      Authorization: `Bearer ${GIST_TOKEN}`,
      Accept: "application/vnd.github+json",
      ...opts.headers
    }
  });

const parseFile = (gist, name, fallback) => {
  try {
    const f = gist.files[name];
    return f && f.content ? JSON.parse(f.content) : fallback;
  } catch {
    return fallback;
  }
};

const res = await api(`/gists/${GIST_ID}`);
if (!res.ok) {
  console.error("gist fetch failed:", res.status);
  process.exit(1);
}
const gist = await res.json();

const doc = parseFile(gist, "dia-todo.json", null);
const subs = parseFile(gist, "push-subs.json", []);
const state = parseFile(gist, "push-state.json", { sent: {} });

if (!doc || !doc.lists) {
  console.log("no task document; nothing to do");
  process.exit(0);
}
if (!Array.isArray(subs) || subs.length === 0) {
  console.log("no push subscriptions; nothing to do");
  process.exit(0);
}

const now = Date.now();
const dueEvents = [];
for (const [key, listName] of [["personal", "Personal"], ["business", "Business"]]) {
  for (const t of doc.lists[key] || []) {
    if (t.done || t.deleted || typeof t.due !== "number") continue;
    if (t.due > now || t.due < now - DUE_LOOKBACK_MS) continue;
    const sentKey = `${t.id || t.text}:${t.due}`;
    if (state.sent[sentKey]) continue;
    dueEvents.push({ sentKey, listName, task: t });
  }
}

if (dueEvents.length === 0) {
  console.log("nothing newly due");
  process.exit(0);
}

webpush.setVapidDetails("mailto:ahmedmohsen18@gmail.com", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const fmt = (ts) =>
  new Intl.DateTimeFormat("en-US", {
    timeZone: "Africa/Cairo",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(ts);

const deadEndpoints = new Set();
for (const ev of dueEvents) {
  const payload = JSON.stringify({
    title: `⏰ ${ev.listName} — due now`,
    body: `${ev.task.text}\nDue ${fmt(ev.task.due)}`,
    tag: `todo-push-${ev.sentKey}`
  });
  for (const sub of subs) {
    try {
      await webpush.sendNotification(sub, payload);
      console.log(`sent "${ev.task.text.slice(0, 40)}" -> ${sub.endpoint.slice(0, 50)}…`);
    } catch (err) {
      const code = err && err.statusCode;
      if (code === 404 || code === 410) deadEndpoints.add(sub.endpoint);
      else console.error("push error", code || err.message);
    }
  }
  state.sent[ev.sentKey] = now;
}

for (const [k, v] of Object.entries(state.sent)) {
  if (v < now - STATE_PRUNE_MS) delete state.sent[k];
}

const files = { "push-state.json": { content: JSON.stringify(state) } };
if (deadEndpoints.size > 0) {
  const alive = subs.filter((s) => !deadEndpoints.has(s.endpoint));
  files["push-subs.json"] = { content: JSON.stringify(alive) };
  console.log(`removed ${deadEndpoints.size} dead subscription(s)`);
}
const patch = await api(`/gists/${GIST_ID}`, { method: "PATCH", body: JSON.stringify({ files }) });
console.log(patch.ok ? `done — ${dueEvents.length} reminder(s) pushed` : `state save failed: ${patch.status}`);

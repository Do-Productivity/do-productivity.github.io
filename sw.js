/* Service worker for My To Do List.
 *
 * Two jobs:
 *   1. Receive Web Push and show notifications.
 *   2. Serve the app with no network at all.
 *
 * The cache name carries the build id, stamped by bump-build.py. A new build
 * therefore gets a brand new cache and the old one is deleted on activate, so
 * a stale shell can never outlive a deploy — the trap that made the phone run
 * old code for hours is structurally impossible here.
 */

var BUILD = "2026-11-04-1544";
var CACHE = "dia-todo-" + BUILD;

/* Everything needed to open the app cold, offline. */
var SHELL = [
  "./",
  "index.html",
  "manifest.json",
  "apple-touch-icon.png"
];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      /* addAll is all-or-nothing; one 404 would leave the app with no cache at
         all, so each entry is allowed to fail on its own. */
      return Promise.all(SHELL.map(function (url) {
        return cache.add(new Request(url, { cache: "reload" })).catch(function () { });
      }));
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(names.map(function (n) {
        return (n !== CACHE && n.indexOf("dia-todo-") === 0) ? caches.delete(n) : null;
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

function isNavigation(req) {
  return req.mode === "navigate" ||
    (req.method === "GET" && (req.headers.get("accept") || "").indexOf("text/html") >= 0);
}

self.addEventListener("fetch", function (event) {
  var req = event.request;
  if (req.method !== "GET") return;

  var url;
  try { url = new URL(req.url); } catch (e) { return; }

  /* GitHub and the account backend must never be served from cache: a stale
     sync document would be merged in as if it were real remote state. */
  if (url.origin !== self.location.origin) return;

  /* The update probe is the one thing that must always hit the network — a
     cached answer would tell the app it is already up to date forever. */
  if (url.pathname.indexOf("version.json") >= 0) {
    event.respondWith(fetch(req).catch(function () {
      return new Response("", { status: 503, statusText: "offline" });
    }));
    return;
  }

  /* The page itself: network first so a deploy is picked up the moment it
     lands, cache as the offline floor. */
  if (isNavigation(req)) {
    event.respondWith(
      fetch(req).then(function (res) {
        if (res && res.ok) {
          var copy = res.clone();
          caches.open(CACHE).then(function (c) { c.put("index.html", copy); });
        }
        return res;
      }).catch(function () {
        return caches.open(CACHE).then(function (c) {
          return c.match("index.html").then(function (hit) {
            return hit || c.match("./", { ignoreSearch: true });
          });
        }).then(function (hit) {
          return hit || new Response(
            "<h1>Offline</h1><p>Open the app once while online and it will work offline after that.</p>",
            { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } }
          );
        });
      })
    );
    return;
  }

  /* Everything else (icon, manifest): serve instantly from cache, refresh in
     the background so the next load is current. */
  event.respondWith(
    caches.open(CACHE).then(function (cache) {
      return cache.match(req, { ignoreSearch: true }).then(function (hit) {
        var net = fetch(req).then(function (res) {
          if (res && res.ok) cache.put(req, res.clone());
          return res;
        }).catch(function () { return hit; });
        return hit || net;
      });
    })
  );
});

self.addEventListener("push", function (event) {
  var data = { title: "⏰ To do — due now", body: "" };
  try {
    if (event.data) data = event.data.json();
  } catch (e) {
    if (event.data) data.body = event.data.text();
  }
  event.waitUntil(
    self.registration.showNotification(data.title || "⏰ To do — due now", {
      body: data.body || "",
      tag: data.tag || undefined,
      icon: "apple-touch-icon.png",
      badge: "apple-touch-icon.png"
    })
  );
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(function (clients) {
      for (var i = 0; i < clients.length; i++) {
        if ("focus" in clients[i]) return clients[i].focus();
      }
      return self.clients.openWindow(".");
    })
  );
});

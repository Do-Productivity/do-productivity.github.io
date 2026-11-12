/* Do. used to run the whole of this address, and its offline helper was
 * installed here. The app now lives under /app/ with its own helper, and
 * this address is the landing page. This file replaces the old helper in
 * any browser that still has it, and its only job is to remove itself.
 */
self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (event) {
  event.waitUntil(self.registration.unregister());
});

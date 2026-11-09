// Stability harness — run in the browser console on a LOCAL copy.
//
//   node preflight.js                     static checks (before deploying)
//   paste this file, then:  runAll()      behaviour + layout, in the browser
//
// Three groups:
//   runLayoutChecks()  the invariants that keep breaking — nothing overflows
//                      its card, the card stays inside the window, the page
//                      does not grow, the toolbar stays reachable.
//   runCoreChecks()    the flows the app exists for: add, tick, untick,
//                      delete, restore, dates, notes, scheduled steps, Today.
//   runSearchTests()   from test-app's sibling test-search.js, if loaded.
//
// Everything is created through the real controls and removed afterwards.
// Probes are tagged, and the cleanup only touches rows carrying the tag.
//
// It refuses to run on a device that syncs: probes made through the UI reach
// the account before cleanup, and cleanup deletes from localStorage without a
// tombstone, so the next sync hands them straight back.

(function () {
  var TAG = "zzapp" + Date.now().toString(36);

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return [].slice.call((root || document).querySelectorAll(sel)); }
  function panel(id) { return $(".panel." + id); }
  function phone() { return window.matchMedia("(max-width: 720px)").matches; }
  function visible(el) {
    if (!el) return false;
    var s = getComputedStyle(el);
    return s.display !== "none" && s.visibility !== "hidden";
  }

  function syncedDevice() {
    return !!(localStorage.getItem("dia_todo_sync_v1") ||
              localStorage.getItem("dia_todo_cloud_session_v1"));
  }

  function makeChecker(out) {
    return function check(name, pass, detail) {
      out.push({ test: name, result: pass ? "PASS" : "FAIL", detail: detail || "" });
      return pass;
    };
  }

  /* ───────────────────────── layout invariants ───────────────────────── */
  // Every bug in this area had the same shape: something was allowed to be
  // wider or taller than the box that was supposed to contain it, and the
  // page absorbed the difference. These check the containment directly, at
  // whatever size the window happens to be, so they can be run at any width.
  async function runLayoutChecks() {
    var out = [];
    var check = makeChecker(out);
    var W = window.innerWidth, H = window.innerHeight;
    var doc = document.documentElement;

    check("no sideways page scroll", doc.scrollWidth <= W + 1,
      doc.scrollWidth + " vs " + W);

    // Above 720 the layout is the window: it must not grow a scrollbar.
    // On a phone the open card is bounded too, by the same rule.
    check("page height stays the window", doc.scrollHeight <= H + 2,
      doc.scrollHeight + " vs " + H);

    var toolbar = $(".toolbar");
    check("toolbar is on screen", !!toolbar && toolbar.getBoundingClientRect().bottom <= H,
      toolbar ? Math.round(toolbar.getBoundingClientRect().bottom) + " vs " + H : "no toolbar");

    var cards = $$(".panel").filter(visible);
    check("at least one card is visible", cards.length > 0, cards.length + " visible");

    cards.forEach(function (p) {
      var name = (p.className.split(" ")[1] || "card");
      var r = p.getBoundingClientRect();

      check(name + ": inside the window vertically", r.bottom <= H + 2,
        Math.round(r.bottom) + " vs " + H);
      check(name + ": inside the window horizontally", r.right <= W + 1 && r.left >= -1,
        Math.round(r.left) + ".." + Math.round(r.right) + " of " + W);
      check(name + ": content is not wider than the card",
        p.scrollWidth <= p.clientWidth + 1,
        p.scrollWidth + "/" + p.clientWidth);

      // nothing inside may paint over the neighbour — this is the one that
      // put the date field on top of the next column on the Duo
      var spills = [];
      $$("*", p).forEach(function (el) {
        if (!visible(el)) return;
        var er = el.getBoundingClientRect();
        if (!er.width) return;
        if (er.right > r.right + 1.5) {
          spills.push((typeof el.className === "string" ? el.className.split(" ")[0] : el.tagName) +
                      " +" + Math.round(er.right - r.right));
        }
      });
      check(name + ": nothing spills out of the right edge", spills.length === 0,
        spills.slice(0, 4).join(", "));

      // the controls you need in order to use the card at all
      var add = $(".add-input", p), btn = $(".add-btn", p);
      if (add && btn) {
        var ar = add.getBoundingClientRect(), br = btn.getBoundingClientRect();
        check(name + ": the add box and its button both fit",
          ar.width > 40 && br.width > 20 && br.right <= r.right + 1,
          Math.round(ar.width) + "px box, button ends " + Math.round(br.right) + " vs " + Math.round(r.right));
      }

      // a list longer than the card must scroll inside it, not push it open
      var list = $(".task-list", p) || $(".note-list", p) || $(".run-list", p);
      if (list && list.scrollHeight > list.clientHeight + 2) {
        var ls = getComputedStyle(list);
        check(name + ": a long list scrolls inside the card",
          ls.overflowY === "auto" || ls.overflowY === "scroll", ls.overflowY);
      }
    });

    return out;
  }

  /* ─────────────────────────── core behaviour ────────────────────────── */
  // `needle` exists because a task does not always keep the text you typed:
  // a date in it is lifted out of the title and set as the due date, which is
  // the whole point of being able to type it there.
  async function addTask(listId, text, needle) {
    var p = panel(listId);
    var input = $(".add-input", p);
    input.value = text;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    $(".add-btn", p).click();
    await sleep(200);
    return $$(".task-row", p).filter(function (r) {
      return r.textContent.indexOf(needle || text) !== -1;
    })[0];
  }

  function rowWith(text, root) {
    return $$(".task-row", root).filter(function (r) {
      return r.textContent.indexOf(text) !== -1;
    })[0];
  }

  async function runCoreChecks() {
    var out = [];
    var check = makeChecker(out);

    if (document.body.classList.contains("view-today")) {
      $("#today-btn").click();
      await sleep(220);
    }
    if (phone()) { $("#tab-personal").click(); await sleep(260); }

    var P = panel("personal");

    // ── add, count, tick, untick, delete, restore ──
    var t1 = TAG + " first";
    var countBefore = parseInt($(".panel-count", P).textContent, 10) || 0;
    var row = await addTask("personal", t1);
    check("a task can be added", !!row, "");
    var countAfter = parseInt($(".panel-count", P).textContent, 10) || 0;
    check("the count goes up with it", countAfter === countBefore + 1,
      countBefore + " -> " + countAfter);

    $(".task-circle", row).click();
    await sleep(220);
    var done = $$(".completed-section", P).filter(function (s) {
      return !s.classList.contains("trash");
    })[0];
    check("ticking moves it to Completed",
      !!done && done.textContent.indexOf(t1) !== -1, "");
    check("the count comes back down",
      (parseInt($(".panel-count", P).textContent, 10) || 0) === countBefore, "");

    var doneRow = rowWith(t1, done);
    $(".task-circle", doneRow).click();
    await sleep(220);
    check("unticking brings it back to the open list",
      !!rowWith(t1, $(".task-list", P)), "");

    row = rowWith(t1, $(".task-list", P));
    $(".task-delete", row).click();
    await sleep(240);
    var trash = $$(".completed-section.trash", P)[0];
    check("deleting moves it to Recently deleted",
      !!trash && trash.textContent.indexOf(t1) !== -1, "");

    var trashRow = rowWith(t1, trash);
    if (trashRow) {
      $(".task-circle", trashRow).click();
      await sleep(240);
      check("a deleted task can be restored", !!rowWith(t1, $(".task-list", P)), "");
    }

    // ── dates typed into the text ──
    var typed = TAG + " call the bank tomorrow at 9am";
    var dated = await addTask("personal", typed, TAG + " call the bank");
    check("a date typed in the text is picked up",
      !!dated && /\d/.test(($(".task-meta", dated) || {}).textContent || ""),
      dated ? (($(".task-meta", dated) || {}).textContent || "no meta") : "not added");
    check("the date words are taken out of the title",
      !!dated && dated.textContent.indexOf("tomorrow at 9am") === -1,
      dated ? dated.textContent.slice(0, 60) : "");

    // ── notes hang off a task ──
    var N = panel("notes");
    var noteText = TAG + " note on a task";
    var ta = $(".note-input", N);
    ta.value = noteText;
    ta.dispatchEvent(new Event("input", { bubbles: true }));
    var sel = $(".note-link-select", N);
    var opt = [].slice.call(sel.options).filter(function (o) { return o.value; })[0];
    if (opt) {
      sel.value = opt.value;
      sel.dispatchEvent(new Event("change", { bubbles: true }));
      $(".note-add-btn", N).click();
      await sleep(220);
      check("a note can be written against a task",
        $$(".note-row", N).some(function (r) { return r.textContent.indexOf(noteText) !== -1; }), "");
    } else {
      check("a note can be written against a task", false, "no open task to attach to");
    }

    // a loose note is refused rather than lost
    ta.value = TAG + " loose note";
    ta.dispatchEvent(new Event("input", { bubbles: true }));
    sel.value = "";
    $(".note-add-btn", N).click();
    await sleep(200);
    check("a note with no task is refused, not swallowed",
      $$(".note-row", N).every(function (r) { return r.textContent.indexOf("loose note") === -1; }) &&
      ($(".note-input", N).value || "").indexOf("loose note") !== -1,
      "the text stays in the box");
    $(".note-input", N).value = "";

    // ── scheduled work ──
    if (phone()) { $("#tab-runs").click(); await sleep(260); }
    else if (document.body.classList.contains("hide-runs")) {
      localStorage.setItem("dia_todo_showruns_v1", "1");
      $("#runs-btn").click();
      await sleep(200);
    }
    var R = panel("runs");
    var schedName = TAG + " scheduled";
    var ri = $(".add-input", R);
    ri.value = schedName;
    ri.dispatchEvent(new Event("input", { bubbles: true }));
    $(".add-btn", R).click();
    await sleep(260);
    var card = $$(".run-card", R).filter(function (c) {
      return c.textContent.indexOf(schedName) !== -1;
    })[0];
    check("a scheduled task can be created", !!card, "");
    if (card) {
      var si = $(".run-add-step", card);
      si.value = TAG + " step one";
      si.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
      await sleep(260);
      card = $$(".run-card", R).filter(function (c) {
        return c.textContent.indexOf(schedName) !== -1;
      })[0];
      check("a step can be added to it",
        !!card && card.textContent.indexOf("step one") !== -1, "");
      var step = $$(".run-step", card)[0];
      if (step) {
        $(".task-circle", step).click();
        await sleep(240);
        card = $$(".run-card", R).filter(function (c) {
          return c.textContent.indexOf(schedName) !== -1;
        })[0];
        check("ticking a step moves the progress on",
          !!card && /1\/1/.test(($(".run-progress", card) || {}).textContent || ""),
          card ? (($(".run-progress", card) || {}).textContent || "") : "");
      }
    }

    // ── Today ──
    $("#today-btn").click();
    await sleep(320);
    check("Today opens", document.body.classList.contains("view-today"), "");
    check("Today lists the dated task",
      ($("#today") || {}).textContent && $("#today").textContent.indexOf(TAG) !== -1,
      "");
    $("#today-btn").click();
    await sleep(260);
    check("Today closes again", !document.body.classList.contains("view-today"), "");

    // ── the data survives a reload-shaped round trip ──
    var stored = localStorage.getItem("dia_todo_personal_v1") || "";
    check("what is on screen is what is stored", stored.indexOf(TAG) !== -1, "");

    // No cleanup check here: each panel keeps its tasks in a closure, so a
    // LATER suite doing anything at all writes that array back and resurrects
    // whatever this one just swept. The sweep that counts is the one in
    // runAll(), after every suite has finished touching the data.
    await cleanup();
    return out;
  }

  // Both namespaces: this file's probes and test-search.js's, for the same
  // resurrection reason — whichever suite runs last has to clear up for all.
  async function cleanup() {
    var PROBE = /zz(app|probe)[a-z0-9]*/;
    function sweep(key, field) {
      try {
        var arr = JSON.parse(localStorage.getItem(key) || "[]");
        localStorage.setItem(key, JSON.stringify(arr.filter(function (o) {
          return !PROBE.test(o[field] || "");
        })));
      } catch (e) {}
    }
    var lists = ["dia_todo_personal_v1", "dia_todo_business_v1"];
    try {
      JSON.parse(localStorage.getItem("dia_todo_customlists_v1") || "[]")
        .forEach(function (l) { lists.push("dia_todo_list_" + l.id + "_v1"); });
    } catch (e) {}
    lists.forEach(function (k) { sweep(k, "text"); });
    sweep("dia_todo_notes_v1", "text");
    sweep("dia_todo_runs_v1", "name");
  }

  /* ──────────────────────────── the runner ───────────────────────────── */
  async function runAll(force) {
    if (syncedDevice() && force !== true) {
      return [{ test: "refused", result: "SKIPPED",
                detail: "this device syncs — probes would reach your account. " +
                        "Run it on a local copy, or runAll(true) if you mean it." }];
    }
    if (/zzapp|zzprobe/.test(document.body.textContent)) {
      return [{ test: "refused", result: "SKIPPED",
                detail: "probes from an earlier run are still on screen — reload, then run again." }];
    }

    // The app records uncaught errors on the device. Anything it records
    // while the suite is driving it is a real fault, even if every assertion
    // below still passes — that is exactly how the detached-node bug hid:
    // the feature was dead, nothing threw an assertion, the console had it.
    function errorsNow() {
      try { return JSON.parse(localStorage.getItem("dia_todo_errors_v1") || "[]"); }
      catch (e) { return []; }
    }
    var errorsBefore = errorsNow().length;

    var out = [];
    out.push({ test: "— LAYOUT at " + window.innerWidth + "x" + window.innerHeight + " —",
               result: "", detail: "" });
    out = out.concat(await runLayoutChecks());

    out.push({ test: "— CORE —", result: "", detail: "" });
    out = out.concat(await runCoreChecks());

    if (typeof window.runSearchTests === "function") {
      out.push({ test: "— SEARCH —", result: "", detail: "" });
      out = out.concat(await window.runSearchTests(force));
    } else {
      out.push({ test: "— SEARCH —", result: "SKIPPED",
                 detail: "load test-search.js too to include it" });
    }

    var fresh = errorsNow().slice(errorsBefore);
    out.push({ test: "nothing threw while the suite ran",
               result: fresh.length ? "FAIL" : "PASS",
               detail: fresh.map(function (e) { return e.k + ": " + e.m; }).join(" | ") });

    // the sweep that counts, now that nothing else will write
    await cleanup();
    var left = 0;
    Object.keys(localStorage).forEach(function (k) {
      if (k.indexOf("dia_todo_") !== 0) return;
      var hits = (localStorage.getItem(k) || "").match(/zz(app|probe)/g);
      if (hits) left += hits.length;
    });
    out.push({ test: "storage left clean", result: left === 0 ? "PASS" : "FAIL",
               detail: left ? left + " probe row(s) left — reload and run again" : "" });

    var failed = out.filter(function (r) { return r.result === "FAIL"; });
    out.push({ test: "— TOTAL —",
               result: failed.length ? failed.length + " FAILED" : "ALL PASS",
               detail: out.filter(function (r) { return r.result; }).length + " checks" });
    return out;
  }

  window.runLayoutChecks = runLayoutChecks;
  window.runCoreChecks = runCoreChecks;
  window.runAll = runAll;
  console.log("runAll() ready — probes tagged " + TAG);
})();

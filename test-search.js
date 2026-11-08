// Search housekeeping — run this in the browser console on the app itself.
//
//   1. open the app (localhost or the live page)
//   2. paste this whole file into the console
//   3. runSearchTests().then(console.table)
//
// It creates its own items through the real UI, searches for them, follows
// each result, checks that the right row ended up on screen and highlighted,
// then removes everything it made. It never touches anything that was already
// there — every probe is tagged with a run id, and the cleanup only removes
// rows carrying that id.
//
// Why through the UI and not against the functions: the half of search that
// breaks is not the matching, it is the LANDING — a drawer that has to be
// opened, a filter that has to be dropped, a column that was put away, an
// accordion on the wrong card. None of that is visible to a unit test.

(function () {
  var TAG = "zzprobe" + Date.now().toString(36);

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return [].slice.call((root || document).querySelectorAll(sel)); }
  function phone() { return window.matchMedia("(max-width: 720px)").matches; }

  function panel(id) { return $(".panel." + id); }

  function rowsIn(p, sel) {
    return $$(sel, p).filter(function (r) { return r.textContent.indexOf(TAG) !== -1; });
  }

  // ── making probes through the real controls ──
  async function addTask(listId, text) {
    var p = panel(listId);
    var input = $(".add-input", p);
    input.value = text;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    $(".add-btn", p).click();
    await sleep(140);
    return rowsIn(p, ".task-row")[0];
  }

  async function addNote(text) {
    var p = panel("notes");
    var input = $(".note-input", p);
    input.value = text;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    // A note has to hang off a task — the app refuses a loose one and says
    // so. Pick the first task the dropdown offers.
    var select = $(".note-link-select", p);
    var option = [].slice.call(select.options).filter(function (o) { return o.value; })[0];
    if (!option) return null;              // no open task to attach to
    select.value = option.value;
    select.dispatchEvent(new Event("change", { bubbles: true }));
    $(".note-add-btn", p).click();
    await sleep(160);
    return rowsIn(p, ".note-row")[0];
  }

  async function addScheduled(name) {
    var p = panel("runs");
    var input = $(".add-input", p);
    input.value = name;
    input.dispatchEvent(new Event("input", { bubbles: true }));
    $(".add-btn", p).click();
    await sleep(180);
    return $$(".run-card", p).filter(function (c) {
      return c.textContent.indexOf(TAG) !== -1;
    })[0];
  }

  async function addStep(card, text) {
    var input = $(".run-add-step", card);
    input.value = text;
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    await sleep(180);
    return $$(".run-step").filter(function (r) { return r.textContent.indexOf(text) !== -1; })[0];
  }

  // ── driving search ──
  async function search(q) {
    var modal = $("#search-modal");
    if (!modal.classList.contains("show")) $("#search-btn").click();
    var input = $("#search-input");
    input.value = q;
    input.dispatchEvent(new Event("input"));
    await sleep(160);
    return $$(".sr-item");
  }

  function closeSearch() { $("#search-modal").classList.remove("show"); }

  async function pickFirst() {
    var first = $(".sr-item");
    if (!first) return null;
    var label = first.textContent.replace(/\s+/g, " ");
    first.click();
    await sleep(850);
    return { label: label, hit: $(".hit") };
  }

  // ── the matrix ──
  // The probes are created through the UI, which means a signed-in device
  // would push them to the account before the cleanup ran, and the cleanup
  // deletes them from localStorage WITHOUT a tombstone — so the next sync
  // would hand them straight back. Run it on a copy that does not sync.
  function syncedDevice() {
    return !!(localStorage.getItem("dia_todo_sync_v1") ||
              localStorage.getItem("dia_todo_cloud_session_v1"));
  }

  async function runSearchTests(force) {
    if (syncedDevice() && force !== true) {
      return [{
        test: "refused",
        result: "SKIPPED",
        detail: "this device syncs — the probes would reach your account. " +
                "Run it on a local copy, or runSearchTests(true) if you mean it."
      }];
    }
    // Probes from an earlier run in THIS page are still in each panel's
    // in-memory array even after storage was swept, and a second run would
    // match them instead of its own fresh ones. A reload is the fix.
    if (/zzprobe/.test(document.body.textContent)) {
      return [{
        test: "refused",
        result: "SKIPPED",
        detail: "probes from a previous run are still on screen — reload the page, then run again."
      }];
    }
    var out = [];
    function check(name, pass, detail) {
      out.push({ test: name, result: pass ? "PASS" : "FAIL", detail: detail || "" });
    }

    var startedOnToday = document.body.classList.contains("view-today");
    if (startedOnToday) $("#today-btn").click();
    await sleep(200);

    // 1. an open task in the first list
    var openText = TAG + " open task";
    await addTask("personal", openText);
    var hits = await search(TAG + " open");
    check("open task is found", hits.length >= 1, hits.length + " result(s)");
    var landed = await pickFirst();
    check("open task lands and flashes",
      !!(landed && landed.hit && landed.hit.textContent.indexOf(TAG) !== -1),
      landed && landed.hit ? landed.hit.className : "no flash");

    // 2. the same task once completed — it drops into a shut drawer
    var row = rowsIn(panel("personal"), ".task-row")[0];
    $(".task-circle", row).click();
    await sleep(200);
    hits = await search(TAG + " open");
    check("completed task is still found", hits.length >= 1,
      hits.length ? $(".sr-item").className : "none");
    check("completed task is labelled", /is-done/.test(($(".sr-item") || {}).className || ""), "");
    landed = await pickFirst();
    var drawer = $$(".completed-section", panel("personal")).filter(function (s) {
      return !s.classList.contains("trash");
    })[0];
    check("completed drawer opens", !!drawer && drawer.classList.contains("open"), "");
    check("completed row flashes", !!(landed && landed.hit), "");

    // 3. deleted — the trash drawer
    row = rowsIn(panel("personal"), ".task-row")[0];
    $(".task-delete", row).click();
    await sleep(220);
    hits = await search(TAG + " open");
    check("deleted task is still found", hits.length >= 1, "");
    check("deleted task is labelled", /is-deleted/.test(($(".sr-item") || {}).className || ""), "");
    landed = await pickFirst();
    var trash = $$(".completed-section.trash", panel("personal"))[0];
    check("trash drawer opens", !!trash && trash.classList.contains("open"), "");

    // 4. a note, including from behind the one-task filter. The filter is the
    //    interesting half: the badge on a task row narrows Notes to that one
    //    task, and a note from any other task is then not rendered at all.
    var noteText = TAG + " note body";
    var noteRow = await addNote(noteText);
    check("note probe created", !!noteRow, noteRow ? "" : "no task to attach to");
    if (noteRow) {
      hits = await search(TAG + " note");
      check("note is found", hits.length >= 1, "");
      check("note says where it lives", /Notes/.test(($(".sr-item") || {}).textContent || ""), "");
      landed = await pickFirst();
      check("note lands and flashes",
        !!(landed && landed.hit && /note-row/.test(landed.hit.className)), "");

      // a completed note, then a deleted one — both have to stay findable
      var liveRow = $$(".note-row").filter(function (r) {
        return r.textContent.indexOf(TAG) !== -1;
      })[0];
      if (liveRow) {
        $(".note-circle", liveRow).click();
        await sleep(220);
        await search(TAG + " note");
        check("completed note is found", $$(".sr-item").length >= 1, "");
        check("completed note is labelled",
          /is-done/.test(($(".sr-item") || {}).className || ""), "");
        landed = await pickFirst();
        check("completed note lands and flashes",
          !!(landed && landed.hit && /note-row/.test(landed.hit.className)), "");

        var doneRow = $$(".note-row").filter(function (r) {
          return r.textContent.indexOf(TAG) !== -1;
        })[0];
        if (doneRow && $(".task-delete", doneRow)) {
          $(".task-delete", doneRow).click();
          await sleep(240);
          await search(TAG + " note");
          check("deleted note is found", $$(".sr-item").length >= 1, "");
          check("deleted note is labelled",
            /is-deleted/.test(($(".sr-item") || {}).className || ""), "");
          landed = await pickFirst();
          var ntrash = $$(".completed-section.trash", panel("notes"))[0];
          check("notes trash drawer opens",
            !!ntrash && ntrash.classList.contains("open"), "");
          check("deleted note lands and flashes",
            !!(landed && landed.hit && /note-row/.test(landed.hit.className)), "");

          // and it can be put back
          var trashRow = $$(".note-row", ntrash).filter(function (r) {
            return r.textContent.indexOf(TAG) !== -1;
          })[0];
          if (trashRow) {
            $(".note-circle", trashRow).click();
            await sleep(240);
            var back = $$(".note-row").filter(function (r) {
              return r.textContent.indexOf(TAG) !== -1 &&
                     !r.closest(".completed-section.trash");
            })[0];
            check("a deleted note can be restored", !!back, "");
          }
        }
      }

      // now narrow Notes to a DIFFERENT task and search again
      var otherBadge = $$(".task-notebtn")[0];   // the note count on a task row
      if (otherBadge) {
        otherBadge.click();
        await sleep(200);
        await search(TAG + " note");
        landed = await pickFirst();
        check("note found from behind the one-task filter",
          !!(landed && landed.hit && /note-row/.test(landed.hit.className)), "");
      }
    }

    // 5. a scheduled task and one of its steps
    var schedName = TAG + " scheduled run";
    var card = await addScheduled(schedName);
    check("scheduled probe created", !!card, "");
    if (card) {
      await addStep(card, TAG + " inner step");
      hits = await search(TAG + " inner");
      check("scheduled step is found", hits.length >= 1, "");
      check("step names its parent", /step in/.test(($(".sr-item") || {}).textContent || ""), "");
      landed = await pickFirst();
      check("step lands and flashes",
        !!(landed && landed.hit && /run-step/.test(landed.hit.className)), "");

      // 6. ...even with the Scheduled column put away (wide screens only)
      if (!phone()) {
        localStorage.setItem("dia_todo_showruns_v1", "0");
        document.body.classList.add("hide-runs");
        await sleep(120);
        await search(TAG + " inner");
        landed = await pickFirst();
        check("hidden Scheduled column comes back",
          !document.body.classList.contains("hide-runs"), "");
      }
    }

    // 7. from inside the Today view
    $("#today-btn").click();
    await sleep(250);
    await search(TAG + " note");
    landed = await pickFirst();
    check("search leaves the Today view",
      !document.body.classList.contains("view-today"), "");

    // 8. ranking: a word that starts with the query beats one that contains it
    await addTask("personal", TAG + " alpharanking");
    await addTask("personal", TAG + " zzz prefixalpharanking");
    hits = await search("alpharanking");
    var firstText = (hits[0] || {}).textContent || "";
    check("word-start ranks above mid-word", / alpharanking/.test(firstText),
      firstText.replace(/\s+/g, " ").slice(0, 48));

    // 9. an empty query explains itself instead of listing everything
    await search("   ");
    check("blank query lists nothing", $$(".sr-item").length === 0, "");
    check("blank query explains itself", !!$(".sr-empty"), "");

    // 10. a query that matches nothing
    await search(TAG + " definitelynothinghere");
    check("no matches says so", /no matches/.test($("#search-count").textContent), "");

    // 11. the keyboard
    closeSearch();
    await sleep(80);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "/", bubbles: true }));
    await sleep(120);
    check("slash opens search", $("#search-modal").classList.contains("show"), "");
    check("slash focuses the box", document.activeElement === $("#search-input"), "");
    await search(TAG);
    var before = $$(".sr-item").length;
    $("#search-input").dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
    await sleep(60);
    var selIndex = $$(".sr-item").indexOf($(".sr-item.sel"));
    check("arrow keys move the selection", before > 1 ? selIndex === 1 : true, "index " + selIndex);
    closeSearch();

    // ── cleanup ──
    // By the prefix, not by this run's tag: each panel keeps its task array in
    // a closure, so any save after a cleanup writes the whole array back and
    // resurrects probes that were already deleted from storage. Sweeping the
    // whole namespace means one reload plus one run always leaves it clean,
    // whatever an earlier run left behind.
    var PROBE = /zzprobe[a-z0-9]+/;
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
    localStorage.removeItem("dia_todo_showruns_v1");

    var left = 0;
    Object.keys(localStorage).forEach(function (k) {
      if (k.indexOf("dia_todo_") !== 0) return;
      var m = (localStorage.getItem(k) || "").match(/zzprobe/g);
      if (m) left += m.length;
    });
    check("storage left clean", left === 0,
      left ? left + " probe row(s) still stored — reload and run once more" : "");

    var failed = out.filter(function (r) { return r.result === "FAIL"; }).length;
    out.push({ test: "— TOTAL —", result: failed ? failed + " FAILED" : "ALL PASS",
               detail: out.length + " checks; reload to clear the probes from view" });
    return out;
  }

  window.runSearchTests = runSearchTests;
  console.log("runSearchTests() ready — probes tagged " + TAG);
})();

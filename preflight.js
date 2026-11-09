#!/usr/bin/env node
/* Preflight: refuse to ship a build that is broken in a way a machine can see.
 *
 *   node preflight.js            check the working copy
 *   node preflight.js --quiet    only print failures
 *
 * bump-build.py runs this BEFORE stamping, so a build id is never minted for
 * a file that fails. The point is not to prove the app works — the browser
 * harnesses do that — it is to catch the specific ways this file has broken
 * before, each of which shipped silently and was found by a person:
 *
 *   - a syntax error in the inline script (the whole app is one <script>, so
 *     one stray brace takes everything with it)
 *   - index.html, sw.js and version.json disagreeing about the build id, so
 *     devices never learn there is an update
 *   - getElementById for an id that is not in the page: the button that was
 *     never added, the handler that quietly does nothing (tab-count-runs)
 *   - two ids the same, so one of them is unreachable
 *   - unbalanced braces in the stylesheet, which silently drops every rule
 *     after the mistake
 *   - a service worker that names a file it does not have
 */
"use strict";

var fs = require("fs");
var path = require("path");
var vm = require("vm");

var here = __dirname;
var quiet = process.argv.indexOf("--quiet") !== -1;
var fails = [];
var warns = [];
var notes = [];

function fail(what, detail) { fails.push({ what: what, detail: detail || "" }); }
function warn(what, detail) { warns.push({ what: what, detail: detail || "" }); }
function note(what, detail) { notes.push({ what: what, detail: detail || "" }); }

function read(name) {
  try { return fs.readFileSync(path.join(here, name), "utf8"); }
  catch (e) { fail("missing file", name); return null; }
}

var html = read("index.html");
var sw = read("sw.js");
var versionRaw = read("version.json");
if (html === null || sw === null) { report(); process.exit(1); }

/* ── 1. the inline script compiles ─────────────────────────────────────── */
var scripts = [];
html.replace(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g, function (_, body) {
  scripts.push(body);
  return _;
});
if (!scripts.length) fail("no inline script found in index.html");
scripts.forEach(function (src, i) {
  try { new vm.Script(src, { filename: "index.html:script[" + i + "]" }); }
  catch (e) { fail("inline script " + i + " does not compile", e.message); }
});
[["sw.js", sw]].forEach(function (pair) {
  try { new vm.Script(pair[1], { filename: pair[0] }); }
  catch (e) { fail(pair[0] + " does not compile", e.message); }
});
["test-search.js", "test-due-dates.js", "test-app.js"].forEach(function (name) {
  var p = path.join(here, name);
  if (!fs.existsSync(p)) return;
  try { new vm.Script(fs.readFileSync(p, "utf8"), { filename: name }); }
  catch (e) { fail(name + " does not compile", e.message); }
});

/* ── 2. one build id, agreed everywhere ────────────────────────────────── */
function buildIn(text, label) {
  var all = text.match(/var BUILD = "([^"]*)"/g) || [];
  if (all.length === 0) { fail("no BUILD constant in " + label); return null; }
  if (all.length > 1) fail("more than one BUILD constant in " + label, all.length + " found");
  return /var BUILD = "([^"]*)"/.exec(all[0])[1];
}
var htmlBuild = buildIn(html, "index.html");
var swBuild = buildIn(sw, "sw.js");
var jsonBuild = null;
try { jsonBuild = JSON.parse(versionRaw || "{}").build; }
catch (e) { fail("version.json is not valid JSON", e.message); }

if (htmlBuild && swBuild && htmlBuild !== swBuild) {
  fail("index.html and sw.js disagree about the build", htmlBuild + " vs " + swBuild);
}
if (htmlBuild && jsonBuild && htmlBuild !== jsonBuild) {
  fail("version.json disagrees with index.html", jsonBuild + " vs " + htmlBuild +
       " — devices poll version.json, so they would never be told to update");
}
if (htmlBuild) note("build id", htmlBuild);

/* ── 3. ids: unique, and every one the script asks for exists ──────────── */
var staticIds = Object.create(null);
var dupes = [];
var idRe = /\bid="([^"]+)"/g, m;
while ((m = idRe.exec(html))) {
  if (staticIds[m[1]]) dupes.push(m[1]);
  staticIds[m[1]] = true;
}
if (dupes.length) fail("duplicate element ids", dupes.join(", "));

/* ids the script creates for itself count as present */
var madeIds = Object.create(null);
var mk = /\.id\s*=\s*"([^"]+)"/g;
while ((m = mk.exec(html))) madeIds[m[1]] = true;

var missing = [];
var get = /getElementById\(\s*"([^"]+)"\s*\)/g;
while ((m = get.exec(html))) {
  var id = m[1];
  if (!staticIds[id] && !madeIds[id] && missing.indexOf(id) === -1) missing.push(id);
}
if (missing.length) {
  fail("getElementById for ids that are not in the page", missing.join(", ") +
       " — the handler compiles, finds nothing, and does nothing");
}

/* ── 4. the stylesheet is balanced ─────────────────────────────────────── */
var styles = [];
html.replace(/<style[^>]*>([\s\S]*?)<\/style>/g, function (_, body) { styles.push(body); return _; });
if (!styles.length) fail("no <style> block found");
styles.forEach(function (css, i) {
  var depth = 0, line = 1, badLine = 0;
  for (var c = 0; c < css.length; c++) {
    var ch = css[c];
    if (ch === "\n") line++;
    else if (ch === "{") depth++;
    else if (ch === "}") { depth--; if (depth < 0 && !badLine) badLine = line; }
  }
  if (depth !== 0 || badLine) {
    fail("stylesheet " + i + " braces are unbalanced",
         "depth ends at " + depth + (badLine ? ", first stray } near line " + badLine : "") +
         " — everything after the mistake is silently dropped");
  }
});

/* ── 5. the service worker's shell exists ──────────────────────────────── */
var shell = /var SHELL = \[([\s\S]*?)\];/.exec(sw);
if (!shell) warn("no SHELL list in sw.js");
else {
  (shell[1].match(/"([^"]+)"/g) || []).forEach(function (q) {
    var f = q.slice(1, -1);
    if (f === "./" || /^https?:/.test(f)) return;
    if (!fs.existsSync(path.join(here, f))) {
      fail("service worker caches a file that does not exist", f);
    }
  });
}

/* ── 6. warnings: the quiet overrides that keep biting ─────────────────── */
/* Same selector, same media block, same property declared twice. Sometimes
   deliberate, so it is a warning — but it is how "the rule I added did
   nothing" has happened three times here. */
(function () {
  var css = styles.join("\n");
  var media = "";
  var depth = 0;
  var seen = Object.create(null);
  var dupProps = [];
  var re = /@media([^{]*)\{|([^{}@]+)\{([^{}]*)\}|\}/g;
  var tok;
  while ((tok = re.exec(css))) {
    if (tok[1] !== undefined) { media = tok[1].trim(); depth++; continue; }
    if (tok[2] !== undefined) {
      var sel = tok[2].trim().replace(/\s+/g, " ");
      if (!sel || sel.charAt(0) === "@") continue;
      /* keyframe steps repeat properties by definition */
      if (/^(from|to|\d+%)$/.test(sel)) continue;
      var props = (tok[3] || "").split(";").map(function (p) {
        var at = p.indexOf(":");
        if (at === -1) return null;
        return { name: p.slice(0, at).trim(), value: p.slice(at + 1).trim() };
      }).filter(Boolean);
      props.forEach(function (prop) {
        var key = media + "||" + sel + "||" + prop.name;
        var before = seen[key];
        /* A second declaration is usually a deliberate fallback: the older
           unit first, the newer one after, for browsers that ignore it.
           Only the ones that are NOT that pattern are worth reporting. */
        var isFallback = /dvh|dvw|env\(|min\(|max\(|clamp\(|-webkit-|-moz-/.test(prop.value) ||
                         (before && /dvh|dvw|env\(/.test(before));
        if (before && !isFallback) {
          if (dupProps.length < 12) {
            dupProps.push((media ? "@media" + media + " " : "") + sel + " { " + prop.name + " }");
          }
        }
        seen[key] = prop.value;
      });
      continue;
    }
    if (depth > 0) { depth--; if (depth === 0) media = ""; }
  }
  if (dupProps.length) {
    warn("same property set twice for one selector in one block",
         dupProps.join("  |  ") + (dupProps.length >= 12 ? "  …" : ""));
  }
})();

var kb = Math.round(html.length / 1024);
note("index.html", kb + " KB");
if (kb > 900) warn("index.html is getting large", kb + " KB");

var logs = (html.match(/console\.log\(/g) || []).length;
if (logs) note("console.log calls", String(logs));

/* ── report ────────────────────────────────────────────────────────────── */
function report() {
  if (!quiet) {
    notes.forEach(function (n) { console.log("  · " + n.what + ": " + n.detail); });
    warns.forEach(function (w) {
      console.log("  ! " + w.what + (w.detail ? "\n      " + w.detail : ""));
    });
  }
  fails.forEach(function (f) {
    console.error("  ✗ " + f.what + (f.detail ? "\n      " + f.detail : ""));
  });
  if (!fails.length && !quiet) {
    console.log("preflight OK — " + warns.length + " warning(s)");
  }
}
report();
process.exit(fails.length ? 1 : 0);

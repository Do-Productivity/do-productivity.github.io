#!/usr/bin/env python3
"""Regenerate index.html with the current todo-widget.js embedded.

Run after editing the widget so the install page always hands out the
latest script:   python3 build-page.py
"""
import html
import json
import pathlib

here = pathlib.Path(__file__).parent
code = (here / "todo-widget.js").read_text()

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<title>To Do Widget &mdash; Install</title>
<style>
  :root {
    --paper:#f7f3e9; --card:#fffdf7; --ink:#2b2620; --soft:#6b6259;
    --faint:#a89f93; --rule:#d9d2c2; --red:#c8553d; --blue:#3d6b8c;
    --serif:"Iowan Old Style",ui-serif,Palatino,Georgia,serif;
    --sans:-apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif;
  }
  *{margin:0;padding:0;box-sizing:border-box}
  body{
    background:var(--paper);
    background-image:radial-gradient(circle,#e6dfd0 1px,transparent 1px);
    background-size:22px 22px;
    color:var(--ink); font-family:var(--sans);
    padding:calc(18px + env(safe-area-inset-top)) 16px calc(40px + env(safe-area-inset-bottom));
    -webkit-font-smoothing:antialiased;
  }
  .wrap{max-width:620px;margin:0 auto}
  h1{font-family:var(--serif);font-size:30px;margin-bottom:4px}
  h1 .dot{color:var(--red)}
  .sub{font-size:11px;letter-spacing:2px;text-transform:uppercase;color:var(--faint);margin-bottom:20px}
  .card{background:var(--card);border-radius:12px;border-top:3px solid var(--red);
        box-shadow:0 2px 12px rgba(43,38,32,.1);padding:18px 16px;margin-bottom:16px}
  ol{padding-left:20px;line-height:1.9;font-size:14px;color:var(--soft)}
  ol b{color:var(--ink)}
  ol li{margin-bottom:4px}
  a{color:var(--blue)}
  button{
    display:block;width:100%;font-family:var(--sans);font-size:15px;font-weight:700;
    letter-spacing:.5px;color:#fff;background:var(--red);border:none;border-radius:10px;
    padding:16px;margin:14px 0 6px;cursor:pointer;
  }
  button.done{background:var(--blue)}
  pre{
    background:var(--paper);border:1px solid var(--rule);border-radius:8px;
    padding:12px;overflow-x:auto;font-size:10.5px;line-height:1.5;
    max-height:300px;overflow-y:auto;color:var(--soft);
  }
  .hint{font-size:12px;color:var(--faint);margin-top:10px;line-height:1.7}
  .hint b{color:var(--soft)}
  code{background:var(--paper);border:1px solid var(--rule);border-radius:4px;
       padding:1px 5px;font-size:12px;color:var(--ink)}
  table{width:100%;border-collapse:collapse;margin-top:10px;font-size:12.5px}
  td{padding:6px 4px;border-bottom:1px solid var(--rule);color:var(--soft)}
  td:first-child{width:38%}
  details{margin-top:14px;border-top:1px solid var(--rule);padding-top:12px}
  summary{font-size:13px;font-weight:700;color:var(--soft);cursor:pointer}
</style>
</head>
<body>
<div class="wrap">
  <h1>To&nbsp;Do Widget<span class="dot">.</span></h1>
  <div class="sub">Home screen &middot; iPhone</div>

  <div class="card">
    <ol>
      <li>Install <b><a href="https://apps.apple.com/app/scriptable/id1405459188">Scriptable</a></b> from the App&nbsp;Store (free).</li>
      <li>Tap <b>Copy script</b> below.</li>
      <li>Open Scriptable &rarr; <b>+</b> (top right) &rarr; tap the blank page &rarr; <b>Paste</b>.</li>
      <li>Tap the settings icon, name it <b>To Do</b>, then <b>Done</b>.</li>
      <li>Home Screen: long-press &rarr; <b>Edit</b> &rarr; <b>Add Widget</b> &rarr; <b>Scriptable</b> &rarr; choose a size.</li>
      <li>Long-press the new widget &rarr; <b>Edit Widget</b>, then set:
        <br>&bull; <b>Script:</b> To Do
        <br>&bull; <b>When Interacting:</b> Run Script
        <br>&bull; <b>Parameter:</b> see below</li>
    </ol>

    <table>
      <tr><td><code>personal</code></td><td>Personal card only &mdash; biggest text</td></tr>
      <tr><td><code>business</code></td><td>Business card only &mdash; biggest text</td></tr>
      <tr><td><i>(blank)</i></td><td>Both lists side by side &mdash; smaller text</td></tr>
    </table>

    <button id="copy">Copy script</button>

    <div class="hint">
      <b>Updating from an older version?</b> Copy again and replace the whole script in Scriptable.
      <br><br>
      <b>Text too small?</b> Use a <b>large</b> widget, and set the Parameter to one list rather than
      leaving it blank &mdash; a single card gets much larger type than two side by side.
      <br><br>
      Reads your live synced list, so it always matches the phone and Mac. Tap the widget to open
      the app. The footer shows when it last refreshed.
    </div>

    <details>
      <summary>Show the code</summary>
      <pre id="code">__CODE__</pre>
    </details>
  </div>
</div>
<script>
  var SRC = __JSON__;
  document.getElementById('code').textContent = SRC;
  document.getElementById('copy').addEventListener('click', function () {
    var btn = this;
    function ok(){ btn.textContent = 'Copied \\u2014 now paste into Scriptable'; btn.classList.add('done'); }
    function fallback(){
      var ta = document.createElement('textarea');
      ta.value = SRC; document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy'); ok(); }
      catch(e){ btn.textContent = 'Open "Show the code" and copy manually'; }
      document.body.removeChild(ta);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(SRC).then(ok, fallback);
    } else { fallback(); }
  });
</script>
</body>
</html>
"""

page = TEMPLATE.replace("__CODE__", html.escape(code)).replace("__JSON__", json.dumps(code))
(here / "index.html").write_text(page)
print(f"index.html rebuilt — embeds {len(code)} chars of script")

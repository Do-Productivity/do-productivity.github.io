// App Store pictures with a headline: each is a real simulator screenshot inside a drawn frame, at Apple's exact size.
// usage: node captions.mjs <dir with the plain screenshots> <out dir>
import { chromium } from "playwright";
import { mkdirSync, existsSync, writeFileSync, rmSync } from "node:fs";
const [SRC, OUT] = process.argv.slice(2);

const PHONE = [
  ["01-lists", "Everything to do", "Every list,<br>one place<i>.</i>", "Home, work, notes and plans. One swipe apart."],
  ["02-today", "Today", "Your whole day,<br>one timeline<i>.</i>", "Tasks and meetings together, in the order they happen."],
  ["03-calendar", "Calendar", "To-dos and calendar,<br>finally together<i>.</i>", "Tap an hour to add what needs doing."],
  ["04-type", "Dates and reminders", "Type it the way<br>you say it<i>.</i>", "“Call the bank tomorrow 3pm” sets the reminder."],
  ["05-steps", "Scheduled tasks", "Big jobs,<br>step by step<i>.</i>", "A start, a deadline, and the steps in between."],
  ["06-private", "Private by design", "No account<i>.</i><br>No sign-up<i>.</i>", "Your lists stay on your device unless you turn on sync."],
];
const SETS = {
  "iphone-6.9": { W: 1320, H: 2868, shots: PHONE, eyebrow: 34, h: 118, sub: 46, top: 170, dev: 1060, gap: 96, radius: 150, bezel: 20 },
  // Apple's required size: "iPhone with Dynamic Island (medium display)", 1206 x 2622. Drawn from the large captures.
  "iphone-6.3": { W: 1206, H: 2622, shots: PHONE, src: "iphone-6.9", eyebrow: 31, h: 108, sub: 42, top: 156, dev: 968, gap: 88, radius: 137, bezel: 18 },
  "iphone-duo-outer": { W: 1398, H: 2034, shots: PHONE, eyebrow: 30, h: 96, sub: 40, top: 110, dev: 1010, gap: 70, radius: 104, bezel: 18, tag: "Made for iPhone Duo" },
  // not for the App Store: the same six for an Instagram carousel (4:5) and for LinkedIn
  "social-4x5": { W: 1080, H: 1350, shots: PHONE, src: "iphone-duo-outer", eyebrow: 25, h: 80, sub: 33, top: 64, dev: 640, gap: 46, radius: 70, bezel: 13 },
  "iphone-duo-inner": { W: 2853, H: 2007, eyebrow: 38, h: 124, sub: 0, top: 96, dev: 2120, gap: 78, radius: 86, bezel: 20, tag: "Made for iPhone Duo", oneLine: true,
    shots: [["01-four-lists", "Made for iPhone Duo", "Open it. Every list, side by side<i>.</i>", ""], ["02-today", "Made for iPhone Duo", "Your whole day, on the big screen<i>.</i>", ""]] },
};

const b = await chromium.launch();
for (const [name, s] of Object.entries(SETS)) {
  mkdirSync(`${OUT}/${name}`, { recursive: true });
  const p = await b.newPage({ viewport: { width: s.W, height: s.H }, deviceScaleFactor: 1 });
  for (const [file, eyebrow, head, sub] of s.shots) {
    const img = `${SRC}/${s.src || name}/${file}.jpg`;
    if (!existsSync(img)) { console.log("missing", img); continue; }
    const html = `<!doctype html><meta charset="utf-8"><style>
      html,body{margin:0;width:${s.W}px;height:${s.H}px;overflow:hidden}
      body{background-color:#f7f3e9;background-image:radial-gradient(rgba(43,38,32,.10) 2.2px,transparent 2.8px);background-size:64px 64px;
           color:#2b2620;font-family:-apple-system,"Helvetica Neue",sans-serif;text-align:center}
      .eb{padding-top:${s.top}px;font-weight:700;font-size:${s.eyebrow}px;letter-spacing:.24em;text-transform:uppercase;color:#c8553d}
      h1{margin:${Math.round(s.h * 0.34)}px 0 0;font:700 ${s.h}px/1.04 "Iowan Old Style",Georgia,serif;letter-spacing:-.012em}
      h1 i{font-style:normal;color:#c8553d}
      .sub{margin-top:${Math.round(s.h * 0.36)}px;font-size:${s.sub}px;color:#6b6259}
      .dev{width:${s.dev}px;margin:${s.gap}px auto 0;padding:${s.bezel}px;border-radius:${s.radius}px;box-sizing:border-box;
           background:linear-gradient(140deg,#57514b 0%,#1b1815 22%,#0e0c0a 70%,#46413b 100%);box-shadow:0 0 0 2px #2b2723,0 50px 110px rgba(43,38,32,.30)}
      .dev img{display:block;width:100%;border-radius:${s.radius - s.bezel}px}
    </style><div class="eb">${s.tag || eyebrow}</div><h1>${head}</h1>${sub && s.sub ? `<div class="sub">${sub}</div>` : ""}
    <div class="dev"><img src="file://${img}"></div>`;
    // a page made from a string may not load local pictures; one opened from a file may
    const tmp = `${OUT}/_page.html`;
    writeFileSync(tmp, html);
    await p.goto("file://" + tmp);
    await p.waitForFunction(() => { const i = document.querySelector("img"); return i.complete && i.naturalWidth > 0; });
    await p.screenshot({ path: `${OUT}/${name}/${file}.jpg`, type: "jpeg", quality: 93 });
    console.log(name, file);
  }
  await p.close();
}
rmSync(`${OUT}/_page.html`, { force: true });
await b.close();

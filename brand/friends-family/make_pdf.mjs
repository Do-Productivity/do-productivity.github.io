// The three-page PDF for friends and family.
//
//   npm i -D playwright && npx playwright install chromium   (once)
//   node brand/friends-family/make_pdf.mjs "$PWD/brand/friends-family/index.html" \
//        "$PWD/brand/friends-family/Do-friends-and-family.pdf" /tmp
//
// It prints a line per page saying whether anything spills off it, writes a
// picture of each page to the third argument to look at, then the PDF.
//
// The pictures in img/ are of invented tasks and meetings — the same made-up
// day as brand/launch-plan/make_shots.mjs — never Miha's own. The prices on
// page 3 are typed in index.html: change them there if the plans change.
import { chromium } from "playwright";
const [src, out, shots] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 794, height: 1123 }, deviceScaleFactor: 1.5 });
await page.goto("file://" + src, { waitUntil: "load" });
await page.waitForTimeout(500);
// anything spilling out of a page, or crowding the footer?
const report = await page.evaluate(() => [...document.querySelectorAll(".page")].map((p, i) => {
  const r = p.getBoundingClientRect();
  let worst = 0, who = "";
  p.querySelectorAll("*").forEach((e) => {
    const b = e.getBoundingClientRect();
    if (!b.width) return;
    const o = Math.max(b.bottom - r.bottom, b.right - r.right);
    if (o > worst) { worst = o; who = String(e.className || e.tagName); }
  });
  const foot = p.querySelector(".foot");
  const prev = foot.previousElementSibling.getBoundingClientRect();
  return { page: i + 1, spill: Math.round(worst), who, gapAboveFoot: Math.round(foot.getBoundingClientRect().top - prev.bottom) };
}));
console.log(JSON.stringify(report));
const pages = await page.$$(".page");
for (let i = 0; i < pages.length; i++) await pages[i].screenshot({ path: shots + "/p" + (i + 1) + ".png" });
await page.pdf({ path: out, format: "A4", printBackground: true, margin: { top: 0, right: 0, bottom: 0, left: 0 } });
await browser.close();

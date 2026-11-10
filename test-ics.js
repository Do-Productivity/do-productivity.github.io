// Pull the ICS parser out of the shipped file and test it, the same way
// test-due-dates.js does for the date parser: the tested code is the code.
const fs = require('fs');
const html = fs.readFileSync(require('path').join(__dirname, 'index.html'), 'utf8');

function grab(startMarker, endMarker) {
  const a = html.indexOf(startMarker);
  const b = html.indexOf(endMarker, a);
  if (a === -1 || b === -1) throw new Error('markers not found: ' + startMarker);
  return html.slice(a, b);
}
const src = grab('  function icsUnfold(text)', '  // ── Fetching ──');
const startOfDay = (ts, plus) => { const d = new Date(ts); d.setHours(0,0,0,0); if (plus) d.setDate(d.getDate()+plus); return d.getTime(); };
const mod = new Function('startOfDay', src + '; return {icsParse, icsExpand, icsTime, icsUnfold};')(startOfDay);

let pass = 0, fail = 0;
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) pass++; else { fail++; console.log('FAIL ' + name + '\n  got  ' + JSON.stringify(got) + '\n  want ' + JSON.stringify(want)); }
}

// 1. folded lines — the classic truncation bug
const folded = 'BEGIN:VEVENT\r\nSUMMARY:[2027 Planning] Engage Deeply -\r\n  Consumer KRs\r\nDTSTART:20261110T100000Z\r\nDTEND:20261110T120000Z\r\nEND:VEVENT';
let evs = mod.icsParse(folded);
check('unfolds a wrapped SUMMARY', evs[0].summary, '[2027 Planning] Engage Deeply - Consumer KRs');

// 2. escaped characters
evs = mod.icsParse('BEGIN:VEVENT\nSUMMARY:Review\\, budget\; then lunch\nDTSTART:20261110T090000Z\nEND:VEVENT');
check('unescapes commas and semicolons', evs[0].summary, 'Review, budget; then lunch');

// 3. all-day
evs = mod.icsParse('BEGIN:VEVENT\nSUMMARY:Travel\nDTSTART;VALUE=DATE:20261110\nDTEND;VALUE=DATE:20261111\nEND:VEVENT');
check('all-day detected', evs[0].allDay, true);

// 4. UTC vs floating
const utc = mod.icsTime('20261110T140000Z');
check('Z parsed as UTC', utc.ts, Date.UTC(2026,10,10,14,0,0));
const floating = mod.icsTime('20261110T140000');
check('no Z parsed as local', floating.ts, new Date(2026,10,10,14,0,0).getTime());

// 5. weekly repeat with BYDAY across a week
const weekly = mod.icsParse([
  'BEGIN:VEVENT','SUMMARY:Standup','DTSTART:20261109T080000Z','DTEND:20261109T081500Z',
  'RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR','END:VEVENT'].join('\n'))[0];
const from = Date.UTC(2026,10,9), to = Date.UTC(2026,10,16);
const hits = mod.icsExpand(weekly, from, to);
check('weekly BYDAY yields three in a week', hits.length, 3);

// 6. COUNT is honoured
const counted = mod.icsParse([
  'BEGIN:VEVENT','SUMMARY:Three only','DTSTART:20261109T080000Z',
  'RRULE:FREQ=DAILY;COUNT=3','END:VEVENT'].join('\n'))[0];
check('COUNT=3 stops at three', mod.icsExpand(counted, from, Date.UTC(2026,10,30)).length, 3);

// 7. UNTIL is honoured
const untilEv = mod.icsParse([
  'BEGIN:VEVENT','SUMMARY:Until','DTSTART:20261109T080000Z',
  'RRULE:FREQ=DAILY;UNTIL=20261111T000000Z','END:VEVENT'].join('\n'))[0];
check('UNTIL stops the series', mod.icsExpand(untilEv, from, Date.UTC(2026,10,30)).length, 2);

// 8. a non-repeating event outside the window is not returned
const once = mod.icsParse('BEGIN:VEVENT\nSUMMARY:Old\nDTSTART:20200101T090000Z\nDTEND:20200101T100000Z\nEND:VEVENT')[0];
check('out-of-range single event skipped', mod.icsExpand(once, from, to).length, 0);

// 9. a malformed RRULE must not hang
const weird = mod.icsParse('BEGIN:VEVENT\nSUMMARY:Weird\nDTSTART:20261109T080000Z\nRRULE:FREQ=FORTNIGHTLY\nEND:VEVENT')[0];
const t0 = Date.now();
mod.icsExpand(weird, from, to);
check('unknown FREQ returns quickly', Date.now() - t0 < 500, true);

// 10. several events in one file
evs = mod.icsParse(['BEGIN:VCALENDAR',
  'BEGIN:VEVENT','SUMMARY:One','DTSTART:20261110T090000Z','END:VEVENT',
  'BEGIN:VEVENT','SUMMARY:Two','DTSTART:20261110T110000Z','END:VEVENT',
  'END:VCALENDAR'].join('\r\n'));
check('two events parsed', evs.map(e => e.summary), ['One','Two']);

console.log(pass + '/' + (pass+fail) + ' ICS checks passed');
process.exit(fail ? 1 : 0);

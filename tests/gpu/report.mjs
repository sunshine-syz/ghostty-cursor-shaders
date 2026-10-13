// Usage: node report.mjs <dumped-dom.html>
// Prints the results from the test page. Exits 1 when a test fails.
import { readFileSync } from 'node:fs';

const dom = readFileSync(process.argv[2], 'utf8');
const m = dom.match(/<pre id="out">([\s\S]*?)<\/pre>/);
if (!m) { console.log('The page wrote no result.'); process.exit(2); }
const text = m[1].replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
if (text === 'NOT RUN') { console.log('The page script did not run.'); process.exit(2); }
const data = JSON.parse(text);
if (data.fatal) { console.log('FATAL', data.fatal); process.exit(2); }

console.log(`GPU: ${data.renderer}`);
// Prints restoreBad and redX/blueX only for the tests that check them.
const fmt = (r, expect) => `changed=${r.changed} nan=${r.nan} minAlpha=${r.minAlpha}` +
  (expect.includes('restoreOK') ? ` restoreBad=${r.restoreBad}` : '') +
  (expect.includes('headLeads') ? ` redX=${r.redX} blueX=${r.blueX}` : '');
let fails = 0;
for (const r of data.results) {
  if (r.verdict !== 'PASS') fails++;
  const base = r.baselineDiff !== undefined ? `  baseline diff=${r.baselineDiff}` : '';
  console.log(`${r.verdict.padEnd(5)} ${r.file.padEnd(24)} ${r.name.padEnd(38)} ${r.m ? fmt(r.m, r.expect) : ''}${base}` +
    (r.notes.length ? `  <- ${r.notes.join('; ')}` : ''));
}
console.log(`\n${data.results.length - fails}/${data.results.length} passed`);
process.exit(fails ? 1 : 0);

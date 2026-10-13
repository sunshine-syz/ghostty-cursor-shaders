// Usage: node build.mjs <shader-dir> <out.html> [<baseline-dir>]
// Writes a self-contained WebGL2 test page from the shaders and TESTS below.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [shaderDir, outPath, baselineDir] = process.argv.slice(2);
const here = dirname(fileURLToPath(import.meta.url));

const PULSES = ['sonic_boom_cursor', 'ripple_cursor', 'rectangle_boom_cursor', 'ripple_rectangle_cursor'];
const TRAILS = ['cursor_warp', 'cursor_tail', 'cursor_sweep'];
const load = (dir) => Object.fromEntries([...PULSES, ...TRAILS].map((n) => [n, readFileSync(join(dir, `${n}.glsl`), 'utf8')]));
const SOURCES = { current: load(shaderDir), baseline: baselineDir ? load(baselineDir) : null };

// Cells are 16x32 px on a 640x480 pane. Cursor rects are (left, top, width, height),
// y up, as Ghostty sends them. A cursor on a wide character is two cells wide.
const BLOCK = 0, BAR = 2, UNDERLINE = 3;
const gold = [0.9, 0.8, 0.2, 1.0];
const live = {
  tChange: 10.0, tFocus: 1.0, focus: 1, visible: 1,
  bg: [0.1, 0.1, 0.1, 1.0], curColor: gold, prevColor: gold, prevStyle: BLOCK, curStyle: BLOCK,
};
const TESTS = [];

// Pulse shaders, 1/3 into the 0.15 s pulse.
const block = [320, 256, 16, 32], bar = [319, 256, 2, 32], wide = [336, 256, 32, 32];
const toBar = { prev: block, cur: bar, curStyle: BAR };
for (const file of PULSES) {
  const P = (name, u, expect, extra = {}) => TESTS.push({ file, name, u: { ...live, time: 10.05, ...u }, expect, ...extra });
  P('block -> bar pulses', toBar, ['changed>0', 'nan==0']);
  P('bar -> block pulses', { prev: bar, cur: block, prevStyle: BAR }, ['changed>0', 'nan==0']);
  P('move onto wide char: no pulse', { prev: block, cur: wide }, ['changed==0']);
  P('move off wide char: no pulse', { prev: wide, cur: [368, 256, 16, 32] }, ['changed==0']);
  P('first cursor (prev zeros): no pulse', { prev: [0, 0, 0, 0], cur: block }, ['changed==0']);
  P('cursor alpha 0.5 keeps window alpha', { ...toBar, curColor: [0.9, 0.8, 0.2, 0.5] }, ['changed>0', 'minAlpha==1']);
  P('BLUR = 0', toBar, ['changed>0', 'nan==0'], { override: { BLUR: '0.0' } });
  P('unfocused split: no pulse', { ...toBar, focus: 0 }, ['changed==0']);
  P('hidden cursor: no pulse', { ...toBar, visible: 0 }, ['changed==0']);
  P('focus gain: no pulse', { prev: bar, cur: block, prevStyle: BAR, tFocus: 10.0 }, ['changed==0']);
  P('after the pulse: nothing', { ...toBar, time: 10.5 }, ['changed==0']);
  P('block -> underline: no pulse', { prev: block, cur: [320, 226, 16, 2], curStyle: UNDERLINE }, ['changed==0']);
}

// Trail shaders, mid-animation.
const elapsed = { cursor_warp: 0.08, cursor_tail: 0.04, cursor_sweep: 0.06 };
const from = [64, 416, 16, 32], diag = [384, 224, 16, 32];
const drawn = ['changed>0', 'nan==0', 'restoreOK'];
for (const file of TRAILS) {
  const T = (name, u, expect, extra = {}) =>
    TESTS.push({ file, name, u: { ...live, time: 10.0 + elapsed[file], ...u }, expect, ...extra });
  T('diagonal move', { prev: from, cur: diag }, drawn);
  T('horizontal move', { prev: [64, 256, 16, 32], cur: [384, 256, 16, 32] }, drawn);
  T('vertical move', { prev: from, cur: [64, 96, 16, 32] }, drawn);
  T('BLUR = 0, diagonal move', { prev: from, cur: diag }, drawn, { override: { BLUR: '0.0' } });
  T('unfocused split: no trail', { prev: from, cur: diag, focus: 0 }, ['changed==0']);
  T('1-row move: no trail', { prev: [64, 256, 16, 32], cur: [64, 224, 16, 32] }, ['changed==0']);
  T('first move (prev zeros): no trail', { prev: [0, 0, 0, 0], cur: diag }, ['changed==0']);
}

// cursor_tail long move: red head, blue tail, linear ease, 360 px (1.5 shader units).
// At p = 0.86 the delayed end has passed the eased end, and the head must still lead.
const colors = {
  override: { TRAIL_COLOR: 'vec4(1.0, 0.0, 0.0, 1.0)', TRAIL_COLOR_TAIL: 'vec4(0.0, 0.0, 1.0, 1.0)' },
  linearEase: true,
};
const longMove = { ...live, bg: [0, 0, 0, 1], prev: [40, 256, 16, 32], cur: [400, 256, 16, 32] };
for (const p of [0.5, 0.86]) {
  TESTS.push({ file: 'cursor_tail', name: `long move, p=${p}: head leads`, u: { ...longMove, time: 10.0 + 0.1 * p },
    expect: ['changed>0', 'headLeads'], ...colors });
}

const harness = readFileSync(join(here, 'harness.js'), 'utf8');
const json = (v) => JSON.stringify(v).replace(/</g, '\\u003c');
writeFileSync(outPath, `<!doctype html><meta charset="utf-8"><title>cursor shader tests</title>
<pre id="out">NOT RUN</pre>
<script>const SOURCES = ${json(SOURCES)}; const TESTS = ${json(TESTS)};</script>
<script>try {
${harness}
} catch (e) { document.getElementById('out').textContent = JSON.stringify({ fatal: String(e && e.stack || e) }); }</script>
`);
console.log(`${TESTS.length} tests`);

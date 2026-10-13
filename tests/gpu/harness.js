// WebGL2 pixel tests. build.mjs injects SOURCES = {current: {name: src}, baseline: {name: src} | null}
// and TESTS. Each test renders one frame with fixed uniforms and checks the pixels. With a
// baseline, it also renders the baseline source and reports the largest pixel difference.
// The JSON result goes to <pre id="out">.
const W = 640, H = 480;
const out = { renderer: null, results: [] };

const canvas = document.createElement('canvas');
canvas.width = W; canvas.height = H;
const gl = canvas.getContext('webgl2', { antialias: false, premultipliedAlpha: false });
const dbg = gl.getExtension('WEBGL_debug_renderer_info');
out.renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
if (!gl.getExtension('EXT_color_buffer_float')) throw new Error('EXT_color_buffer_float is not available');

// A float target keeps NaN and the exact alpha in the readback.
const target = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, target);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, W, H, 0, gl.RGBA, gl.FLOAT, null);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
const fbo = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, target, 0);

// iChannel0 is one flat "terminal" color.
const bgTex = gl.createTexture();
function setBackground(rgba) {
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, bgTex);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, 1, 1, 0, gl.RGBA, gl.FLOAT, new Float32Array(rgba));
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
}

const VS = `#version 300 es
in vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }`;
// GLSL ES version of tests/ghostty_prefix.glsl, without the uniforms the shaders do not use.
const PREFIX = `#version 300 es
precision highp float;
precision highp int;
uniform vec3 iResolution; uniform float iTime;
uniform vec4 iCurrentCursor; uniform vec4 iPreviousCursor;
uniform vec4 iCurrentCursorColor; uniform vec4 iPreviousCursorColor;
uniform int iCurrentCursorStyle; uniform int iPreviousCursorStyle; uniform int iCursorVisible;
uniform float iTimeCursorChange; uniform float iTimeFocus; uniform int iFocus;
uniform sampler2D iChannel0;
#define CURSORSTYLE_BLOCK 0
#define CURSORSTYLE_BLOCK_HOLLOW 1
#define CURSORSTYLE_BAR 2
#define CURSORSTYLE_UNDERLINE 3
#define CURSORSTYLE_LOCK 4
out vec4 _fragColor;
void mainImage(out vec4 fragColor, in vec2 fragCoord);
`;
const SUFFIX = `\nvoid main() { mainImage(_fragColor, gl_FragCoord.xy); }\n`;

const vbo = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);

function replaceOnce(src, re, rep, what) {
  if (!re.test(src)) throw new Error(`source edit did not match: ${what}`);
  return src.replace(re, rep);
}

// Source edits for one test. Overrides run before the color globals become #defines.
function transform(src, t) {
  for (const [name, value] of Object.entries(t.override || {})) {
    src = replaceOnce(src, new RegExp(`^(const )?(float|vec4) ${name} = [^;]+;`, 'm'), `$1$2 ${name} = ${value};`, name);
  }
  if (t.linearEase) {
    src = replaceOnce(src, /^float ease\(float x\) \{/m, 'float easeOff(float x) {', 'ease');
    src = replaceOnce(src, /^float getSdfRectangle/m, 'float ease(float x) { return x; }\nfloat getSdfRectangle', 'ease insert');
  }
  // Older pulse shaders overload the built-in normalize(), which GLSL ES rejects.
  // The rename does not change behavior, so an old baseline still compiles.
  if (/^vec2 normalize\(vec2 value/m.test(src)) src = src.replace(/\bnormalize\(/g, 'toShaderSpace(');
  // GLSL ES rejects a global initialized from a uniform.
  return src.replace(/^vec4 (COLOR|TRAIL_COLOR|TRAIL_COLOR_TAIL) = ([^;]+);/gm, '#define $1 ($2)');
}

function compile(fsSrc) {
  const mk = (type, s) => {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, s); gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh));
    return sh;
  };
  const prog = gl.createProgram();
  gl.attachShader(prog, mk(gl.VERTEX_SHADER, VS));
  gl.attachShader(prog, mk(gl.FRAGMENT_SHADER, fsSrc));
  gl.bindAttribLocation(prog, 0, 'p');
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
  return prog;
}

function render(prog, u) {
  gl.useProgram(prog);
  const loc = (n) => gl.getUniformLocation(prog, n);
  const f4 = (n, v) => { const l = loc(n); if (l) gl.uniform4fv(l, v); };
  const f1 = (n, v) => { const l = loc(n); if (l) gl.uniform1f(l, v); };
  const i1 = (n, v) => { const l = loc(n); if (l) gl.uniform1i(l, v); };
  const r = loc('iResolution'); if (r) gl.uniform3f(r, W, H, 1);
  f1('iTime', u.time); f1('iTimeCursorChange', u.tChange); f1('iTimeFocus', u.tFocus);
  f4('iCurrentCursor', u.cur); f4('iPreviousCursor', u.prev);
  f4('iCurrentCursorColor', u.curColor); f4('iPreviousCursorColor', u.prevColor);
  i1('iCurrentCursorStyle', u.curStyle); i1('iPreviousCursorStyle', u.prevStyle);
  i1('iCursorVisible', u.visible); i1('iFocus', u.focus); i1('iChannel0', 0);
  setBackground(u.bg);
  gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
  gl.viewport(0, 0, W, H);
  gl.enableVertexAttribArray(0);
  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  const px = new Float32Array(W * H * 4);
  gl.readPixels(0, 0, W, H, gl.RGBA, gl.FLOAT, px);
  return px;
}

// u.cur is the current cursor rect (left, top, width, height), y up. restoreBad counts
// pixels inside it (1 px margin) that differ from the input: a trail must leave the
// real cursor visible. redX/blueX are the red- and blue-weighted mean x of the changed
// pixels outside the cursor.
function measure(px, u) {
  let changed = 0, nan = 0, minAlpha = Infinity, restoreBad = 0;
  let rX = 0, rW = 0, bX = 0, bW = 0;
  const [cl, ct, cw, ch] = u.cur;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    const p = [px[i], px[i + 1], px[i + 2], px[i + 3]];
    if (p.some(Number.isNaN)) { nan++; continue; }
    minAlpha = Math.min(minAlpha, p[3]);
    const d = Math.max(...p.map((v, k) => Math.abs(v - u.bg[k])));
    const cx = x + 0.5, cy = y + 0.5;
    const inCursor = cx > cl + 1 && cx < cl + cw - 1 && cy < ct - 1 && cy > ct - ch + 1;
    if (inCursor && d > 1e-6) restoreBad++;
    if (d > 1 / 255) {
      changed++;
      if (!inCursor) { rX += p[0] * cx; rW += p[0]; bX += p[2] * cx; bW += p[2]; }
    }
  }
  return {
    changed, nan, minAlpha: +minAlpha.toFixed(4), restoreBad,
    redX: rW ? +(rX / rW).toFixed(1) : null, blueX: bW ? +(bX / bW).toFixed(1) : null,
  };
}

const maxDiff = (a, b) => { let m = 0; for (let i = 0; i < a.length; i++) m = Math.max(m, Math.abs(a[i] - b[i])); return m; };

const CHECKS = {
  'changed>0': (m) => m.changed > 0,
  'changed==0': (m) => m.changed === 0,
  'nan==0': (m) => m.nan === 0,
  'minAlpha==1': (m) => m.minAlpha === 1,
  'restoreOK': (m) => m.restoreBad === 0,
  'headLeads': (m) => m.redX !== null && m.redX > m.blueX, // red head is right of the blue tail
};

for (const t of TESTS) {
  const row = { file: t.file, name: t.name, expect: t.expect, verdict: 'PASS', notes: [] };
  let px = null;
  try {
    px = render(compile(PREFIX + transform(SOURCES.current[t.file], t) + SUFFIX), t.u);
    row.m = measure(px, t.u);
    for (const c of t.expect) if (!CHECKS[c](row.m)) { row.verdict = 'FAIL'; row.notes.push(c); }
  } catch (e) {
    row.verdict = 'ERROR'; row.notes.push(String(e.message || e).slice(0, 200));
  }
  if (px && SOURCES.baseline) {
    try {
      const base = render(compile(PREFIX + transform(SOURCES.baseline[t.file], t) + SUFFIX), t.u);
      row.baselineDiff = +maxDiff(px, base).toExponential(2);
    } catch (e) {
      row.baselineDiff = `baseline error: ${String(e.message || e).slice(0, 120)}`;
    }
  }
  out.results.push(row);
}
document.getElementById('out').textContent = JSON.stringify(out);

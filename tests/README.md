# Tests

Run these checks from the repo root after you change a shader.

| Command | What it checks | Needs |
| ------- | -------------- | ----- |
| `tests/compile.sh` | Each shader compiles with Ghostty's prefix and glslang settings. | `glslangValidator` |
| `tests/gpu/run.sh [git-ref]` | Shader output, pixel by pixel, for fixed cursor inputs, on this machine's GPU. | Node.js, Google Chrome |
| `tests/ghostty_load.sh` | Ghostty loads each shader through its full path (GLSL → SPIR-V → MSL → Metal). | macOS, Ghostty 1.3.0 or later |

Each command prints one line per shader or test and exits with a non-zero status on a failure.

## compile.sh

Compiles `ghostty_prefix.glsl` + each shader with Vulkan 1.2 and SPIR-V 1.5, as Ghostty does.

`ghostty_prefix.glsl` is a copy of `src/renderer/shaders/shadertoy_prefix.glsl` from
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) at commit `1f80eec05` (MIT license).
Update the copy when Ghostty adds uniforms.

## gpu/run.sh

Renders one frame per test in headless Chrome (WebGL2) and checks the pixels. Examples:

- A block cursor that moves onto a wide character does not pulse.
- A trail leaves the real cursor cell unchanged.
- No pixel is NaN, also with `BLUR = 0.0`.

With a git ref, for example `tests/gpu/run.sh HEAD`, it also renders the shaders at that ref.
It then prints the largest pixel difference per test. A difference of 0 means that the edit
does not change that frame. The difference does not change the PASS or FAIL result.

Notes:

- WebGL uses GLSL ES. The test page changes `vec4 COLOR = iCurrentCursorColor;` (and the
  `TRAIL_COLOR` lines) to `#define`s, because GLSL ES does not allow a global set from a uniform.
- Some tests change a constant (`BLUR`, the trail colors) or the ease in the test page only.
  `gpu/build.mjs` lists the tests.
- The tail color test depends on `DURATION = 0.1` in `cursor_tail.glsl`.
- Set `CHROME` to use another Chrome or Chromium binary.

## ghostty_load.sh

Opens a separate Ghostty copy with all shaders for about 7 seconds, then closes it. It reads
Ghostty's log:

- Pass: `loaded custom shader path=...` for each shader.
- Fail: `spirv error`, `spirv-cross error`, `metal error`, or `error initializing postprocess shaders`.

Notes:

- The copy also reads your Ghostty config. Shaders from your config load too, and their errors
  also show in the result.
- Do not add `--config-default-files=false`. With it, the copy starts with no window and loads no shader.
- The script does not check the animation. Check that by eye in Ghostty.

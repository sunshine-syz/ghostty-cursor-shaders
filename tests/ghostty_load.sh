#!/bin/sh
# Loads every shader in a separate Ghostty copy and checks Ghostty's log. This
# covers Ghostty's full path: GLSL -> SPIR-V -> MSL -> Metal pipeline.
# macOS only. A Ghostty window opens for a few seconds, then closes.
# Usage: tests/ghostty_load.sh [shader.glsl ...]   (default: all shaders in the repo)
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
[ $# -gt 0 ] || set -- "$repo"/*.glsl

# Ghostty logs absolute paths.
for f do
  shift
  set -- "$@" "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
done
log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Each --custom-shader is one argument. Do not add --config-default-files=false:
# with it, the copy starts with no window and no renderer.
(
  for f do shift; set -- "$@" "--custom-shader=$f"; done
  open -na Ghostty.app --env GHOSTTY_LOG=stderr --stderr "$log" --args "$@"
)
sleep 7

pid=$(pgrep -f "ghostty --custom-shader=$1" | head -1 || true)
[ -n "$pid" ] && kill "$pid"

status=0
for f do
  if grep -qF "loaded custom shader path=$f" "$log"; then
    echo "OK   $(basename "$f" .glsl)"
  else
    echo "FAIL $(basename "$f" .glsl): not loaded"
    status=1
  fi
done
# Shaders from your own Ghostty config also load. Their errors show here too.
if grep -E "spirv error|spirv-cross error|metal error|error loading custom shaders|error initializing postprocess shaders" "$log"; then
  status=1
fi
exit $status

#!/bin/sh
# Compiles every shader the way Ghostty does: ghostty_prefix.glsl + shader,
# glslang with Vulkan 1.2 and SPIR-V 1.5.
# Usage: tests/compile.sh [shader.glsl ...]   (default: all shaders in the repo)
set -eu
tests=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$tests")
[ $# -gt 0 ] || set -- "$repo"/*.glsl

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
status=0
for f in "$@"; do
  name=$(basename "$f" .glsl)
  cat "$tests/ghostty_prefix.glsl" "$f" > "$out/$name.frag"
  if glslangValidator -V --target-env vulkan1.2 -S frag -o "$out/$name.spv" "$out/$name.frag" > "$out/$name.log" 2>&1; then
    echo "OK   $name"
  else
    echo "FAIL $name"
    grep -E "ERROR|WARN" "$out/$name.log" | head -5
    status=1
  fi
done
exit $status

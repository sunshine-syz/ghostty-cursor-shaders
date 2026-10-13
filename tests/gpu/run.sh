#!/bin/sh
# Runs the WebGL2 pixel tests in headless Chrome on this machine's GPU.
# Usage: tests/gpu/run.sh [git-ref]
#   git-ref  also renders the shaders at that ref and prints the largest pixel
#            difference per test (for example HEAD, to see what an edit changes).
# Set CHROME to use another Chrome or Chromium binary.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

baseline=
if [ $# -gt 0 ]; then
  baseline="$work/baseline"
  mkdir "$baseline"
  for f in "$repo"/*.glsl; do
    name=$(basename "$f")
    git -C "$repo" show "$1:$name" > "$baseline/$name"
  done
fi

node "$here/build.mjs" "$repo" "$work/test.html" $baseline
# Own profile: the run does not touch your Chrome profile.
"$chrome" --headless=new --user-data-dir="$work/profile" --no-first-run --no-default-browser-check \
  --disable-extensions --enable-unsafe-swiftshader --virtual-time-budget=30000 \
  --dump-dom "file://$work/test.html" > "$work/dom.html" 2> "$work/chrome.log"
node "$here/report.mjs" "$work/dom.html"

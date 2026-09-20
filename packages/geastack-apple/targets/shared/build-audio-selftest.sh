#!/usr/bin/env bash
# Builds and runs the Apple audio backend self-test (apple_audio_selftest.mm).
#
# It compiles the SHIPPING backend (apple_audio.mm — the same translation unit
# the macOS and iOS targets build) against AVFoundation and renders it offline,
# so what it measures is the real synth, scheduler and mixer, not a stand-in.
#
# Output goes to $GEA_AUDIO_SELFTEST_OUT (default: a scratch dir outside the repo
# trees), never to /tmp-only state that matters.
set -euo pipefail

SHARED_DIR="$(cd "$(dirname "$0")" && pwd)"
APPLE_DIR="$(cd "$SHARED_DIR/../.." && pwd)"
# @geastack/core comes from node_modules, the way node resolves it.
resolve_core() {
  node -e "process.stdout.write(require('path').dirname(require.resolve('@geastack/core/package.json',{paths:[process.argv[1],process.cwd()]})))" "$1" 2>/dev/null || true
}
GEA_CORE_DIR="${GEA_CORE_DIR:-$(resolve_core "$APPLE_DIR")}"
[ -n "$GEA_CORE_DIR" ] && [ -d "$GEA_CORE_DIR/include" ] || {
  echo "Cannot resolve @geastack/core — run \`npm install\` in $APPLE_DIR, or set GEA_CORE_DIR" >&2
  exit 1
}
AUDIO_INCLUDE="$GEA_CORE_DIR/include"
# Build output belongs to the caller, not to a sibling repo's working copy.
OUT_DIR="${GEA_AUDIO_SELFTEST_OUT:-$APPLE_DIR/dist/apple-audio-selftest}"

mkdir -p "$OUT_DIR"

# --tsan builds with ThreadSanitizer, which checks the lock-free command ring's
# memory ordering rather than only its observable behaviour.
SANITIZE=()
if [[ "${1:-}" == "--tsan" ]]; then
  SANITIZE=(-fsanitize=thread -g)
  shift
fi

clang++ -std=c++20 -ObjC++ -fobjc-arc -O2 -Wall -Wextra \
  ${SANITIZE[@]+"${SANITIZE[@]}"} \
  -I"$AUDIO_INCLUDE" -I"$SHARED_DIR" \
  -framework AVFoundation -framework Foundation -framework AudioToolbox \
  "$SHARED_DIR/apple_audio.mm" "$SHARED_DIR/apple_audio_selftest.mm" \
  -o "$OUT_DIR/apple-audio-selftest"

echo "built $OUT_DIR/apple-audio-selftest"
echo

"$OUT_DIR/apple-audio-selftest" "$@"

echo
GEA_AUDIO_DISABLED=1 "$OUT_DIR/apple-audio-selftest" --no-device

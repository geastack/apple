#!/usr/bin/env bash
set -euo pipefail

HELPER="$(cd "$(dirname "$0")" && pwd)/heavy-build-lock.sh"

if [ "${1:-}" = "hold" ]; then
  lock_path="$2"
  ready_path="$3"
  # shellcheck source=/dev/null
  source "$HELPER"
  gea_acquire_heavy_build_lock "$lock_path" macos "test-holder"
  trap gea_release_heavy_build_lock EXIT
  touch "$ready_path"
  while true; do sleep 1; done
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gea-heavy-build-lock-test.XXXXXX")"
LOCK_PATH="$TMP_DIR/workspace.lock"
READY_PATH="$TMP_DIR/ready"
HOLDER_PID=""

cleanup() {
  if [ -n "$HOLDER_PID" ]; then
    kill -9 "$HOLDER_PID" 2>/dev/null || true
    wait "$HOLDER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Default developer builds are concurrent and must not create a global lock.
bash -c \
  'set -euo pipefail; source "$1"; gea_acquire_heavy_build_lock "$2" esp32 "test-default"; test ! -e "$2"' \
  _ "$HELPER" "$LOCK_PATH"

GEA_SERIALIZE_HEAVY_BUILDS=1 bash "$0" hold "$LOCK_PATH" "$READY_PATH" &
HOLDER_PID=$!
attempt=0
while [ ! -f "$READY_PATH" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt 100 ]; then
    echo "holder did not acquire the test lock" >&2
    exit 1
  fi
  sleep 0.05
done

set +e
blocked_output="$(GEA_SERIALIZE_HEAVY_BUILDS=1 bash -c 'set -euo pipefail; source "$1"; gea_acquire_heavy_build_lock "$2" esp32 "test-contender"' _ "$HELPER" "$LOCK_PATH" 2>&1)"
blocked_status=$?
set -e
if [ "$blocked_status" -eq 0 ]; then
  echo "a live owner did not block a competing build" >&2
  exit 1
fi
printf '%s\n' "$blocked_output" | grep -q 'kind: macos'
printf '%s\n' "$blocked_output" | grep -q 'target: test-holder'
printf '%s\n' "$blocked_output" | grep -q 'GEA_ALLOW_CONCURRENT_HEAVY_BUILDS=1'

GEA_SERIALIZE_HEAVY_BUILDS=1 GEA_ALLOW_CONCURRENT_HEAVY_BUILDS=1 bash -c \
  'set -euo pipefail; source "$1"; gea_acquire_heavy_build_lock "$2" esp32 "test-override"; gea_release_heavy_build_lock' \
  _ "$HELPER" "$LOCK_PATH" >/dev/null 2>&1

# SIGKILL deliberately leaves the owner file behind. The next acquisition must
# recognize the dead PID and replace it rather than requiring manual cleanup.
kill -9 "$HOLDER_PID"
wait "$HOLDER_PID" 2>/dev/null || true
HOLDER_PID=""
# shellcheck source=/dev/null
source "$HELPER"
GEA_SERIALIZE_HEAVY_BUILDS=1
gea_acquire_heavy_build_lock "$LOCK_PATH" esp32 "test-stale-recovery"
grep -q "^pid=$$\$" "$LOCK_PATH"
grep -q '^kind=esp32$' "$LOCK_PATH"
gea_release_heavy_build_lock
if [ -e "$LOCK_PATH" ]; then
  echo "release left the heavy-build lock behind" >&2
  exit 1
fi

echo "heavy-build lock tests passed"

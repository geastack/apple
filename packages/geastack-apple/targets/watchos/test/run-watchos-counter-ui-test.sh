#!/usr/bin/env bash
set -euo pipefail

# Builds the counter-jsx example for an Apple Watch simulator and runs
# GeaWatchCounterUITests against it: taps reach the app, repaint it, and a tap
# on empty background does not.
#
#   targets/watchos/test/run-watchos-counter-ui-test.sh <path/to/examples/apps/counter-jsx>
#
# The app folder needs its dependencies installed (see targets/watchos/README.md).
# GEA_WATCHOS_SIMULATOR_UDID picks the simulator; otherwise a booted watch, else
# an Apple Watch Series simulator.

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
APP_DIR="${1:-${GEA_WATCHOS_TEST_APP_DIR:-}}"
if [[ -z "$APP_DIR" || ! -f "$APP_DIR/package.json" ]]; then
  echo "usage: $0 <counter-jsx app dir>" >&2
  exit 2
fi
APP_DIR="$(cd "$APP_DIR" && pwd -P)"
OUTPUT_DIR="${GEA_WATCHOS_OUTPUT_DIR:-$APP_DIR/dist/watchos}"

UDID="${GEA_WATCHOS_SIMULATOR_UDID:-$(xcrun simctl list devices available --json | node -e "
  const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  const watches = Object.entries(data.devices || {})
    .filter(([runtime]) => /watchOS/.test(runtime))
    .flatMap(([, list]) => list)
    .filter((d) => d.isAvailable && /^Apple Watch/.test(d.name));
  const preferred = watches.find((d) => d.state === 'Booted') || watches.find((d) => /Series/.test(d.name)) || watches[0];
  if (preferred) process.stdout.write(preferred.udid);
")}"
[[ -n "$UDID" ]] || { echo "No Apple Watch simulator available." >&2; exit 1; }

(cd "$APP_DIR" && GEA_WATCHOS_SKIP_LAUNCH=1 GEA_WATCHOS_OUTPUT_DIR="$OUTPUT_DIR" GEA_WATCHOS_SIMULATOR_UDID="$UDID" \
  bash "$ROOT/targets/watchos/build-watchos.sh" counter-jsx simulator)

xcodebuild \
  -project "$OUTPUT_DIR/counter-jsx/GeaWatch.xcodeproj" \
  -scheme GeaWatch \
  -destination "platform=watchOS Simulator,id=$UDID" \
  -derivedDataPath "$OUTPUT_DIR/.derived-data/counter-jsx-simulator" \
  -resultBundlePath "$OUTPUT_DIR/counter-jsx-ui-tests-$(date +%s).xcresult" \
  test

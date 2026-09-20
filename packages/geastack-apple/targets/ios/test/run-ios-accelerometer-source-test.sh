#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

require_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "[test_ios_accelerometer] $message" >&2
    return 1
  fi
}

reject_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "[test_ios_accelerometer] $message" >&2
    return 1
  fi
}

require_source_count() {
  local file="$1"
  local pattern="$2"
  local expected="$3"
  local message="$4"
  local count
  count="$(grep -Fo "$pattern" "$file" | wc -l | tr -d ' ')"
  if [[ "$count" != "$expected" ]]; then
    echo "[test_ios_accelerometer] $message" >&2
    return 1
  fi
}

require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "#import <CoreMotion/CoreMotion.h>" \
  "iOS accelerometer backend should use CoreMotion"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "CMMotionManager" \
  "iOS accelerometer backend should own a CMMotionManager"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "startDeviceMotionUpdates" \
  "iOS accelerometer backend should start native device-motion updates"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "CMAcceleration" \
  "iOS accelerometer backend should read native acceleration vectors"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "CMRotationRate" \
  "iOS accelerometer backend should read native gyroscope rotation rates"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "kStandardGravity" \
  "iOS accelerometer backend should expose acceleration in m/s^2"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "kRadiansToDegrees" \
  "iOS accelerometer backend should expose gyroscope values in degrees per second"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "tiltFromAxis" \
  "iOS accelerometer backend should provide -100..100 tilt helpers"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "mapCoreMotionAccelerationToGea" \
  "iOS accelerometer backend should convert CoreMotion device axes into GEA axes"
require_source "$ROOT/targets/ios/main/ios_sensors.mm" \
  "mapCoreMotionRotationRateToGea" \
  "iOS accelerometer backend should convert gyroscope axes with the same mapping"
require_source_count "$ROOT/targets/ios/main/ios_sensors.mm" \
  "{ raw.y, -raw.x, raw.z }" \
  "2" \
  "iOS accel and gyro backends should map phone left/right motion onto negative GEA Y"

require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "ios_sensors.mm" \
  "iOS Xcode project generation should compile the Objective-C++ sensor backend"
reject_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "ios_sensors.cpp" \
  "iOS Xcode project generation should not compile the old inert sensor stub"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "CoreMotion.framework" \
  "iOS Xcode project generation should link CoreMotion"

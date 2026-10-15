#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WATCHOS_DIR="$ROOT_DIR/targets/watchos"

# The project is the directory this script was started in, as for iOS: the app
# folder, which every nested `gea` call resolves from too.
BUILD_INVOCATION_CWD="$(pwd -P)"

# Resolve the gea framework through npm the way build-ios.sh does: walk the
# node_modules chain from the app first (a hoisted install), then from this
# package (a linked checkout).
resolve_gea_package_from() {
  node -e '
const fs = require("node:fs")
const path = require("node:path")
let dir = process.argv[1]
while (true) {
  const candidate = path.join(dir, "node_modules", process.argv[2])
  if (fs.existsSync(path.join(candidate, "package.json"))) {
    process.stdout.write(fs.realpathSync(candidate))
    break
  }
  const parent = path.dirname(dir)
  if (parent === dir) break
  dir = parent
}
' "$1" "$2" 2>/dev/null || true
}
resolve_gea_package() {
  local start found
  for start in "$BUILD_INVOCATION_CWD" "$ROOT_DIR"; do
    found="$(resolve_gea_package_from "$start" "$1")"
    if [[ -n "$found" ]]; then
      printf '%s' "$found"
      return 0
    fi
  done
}
GEA_CORE="$(resolve_gea_package @geastack/core)"
[ -n "$GEA_CORE" ] && [ -f "$GEA_CORE/package.json" ] || { echo "Cannot resolve @geastack/core from $BUILD_INVOCATION_CWD — add @geastack/apple to the app's dependencies and run 'npm install' there" >&2; exit 1; }
GEA_COMPILER="$(resolve_gea_package @geastack/compiler)"
[ -n "$GEA_COMPILER" ] && [ -f "$GEA_COMPILER/package.json" ] || { echo "Cannot resolve @geastack/compiler from $BUILD_INVOCATION_CWD — add @geastack/apple to the app's dependencies and run 'npm install' there" >&2; exit 1; }
GEA_HOST_DIR="${GEA_HOST_DIR:-$GEA_CORE/../host}"
GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-$GEA_CORE/../engine}"
GEA_ELEMENTS_DIR="${GEA_ELEMENTS_DIR:-$GEA_CORE/../elements}"
GEA_GEAOS_PACKAGE_DIR="${GEA_GEAOS_PACKAGE_DIR:-$GEA_CORE/../geaos}"
# gea_sources.mjs runs as a child process and reads these from the environment.
export GEA_CORE GEA_HOST_DIR GEA_ENGINE_DIR GEA_ELEMENTS_DIR GEA_GEAOS_PACKAGE_DIR
GEA_CLI="${GEA_CLI_BIN:-}"
if [[ -z "$GEA_CLI" ]]; then
  GEA_CLI="$(node -e 'process.stdout.write(require("path").join(process.argv[1], "bin", "gea.mjs"))' "$(resolve_gea_package @geastack/cli)" 2>/dev/null || true)"
  if [[ ! -f "$GEA_CLI" ]]; then
    GEA_CLI="$(command -v gea || true)"
  fi
fi
[ -n "$GEA_CLI" ] && [ -f "$GEA_CLI" ] || { echo "Cannot locate GeaStack CLI — set GEA_CLI_BIN to gea.mjs, install @geastack/cli locally, or add gea to PATH" >&2; exit 1; }

# Framework sources from the shared manifest, curated like iOS: no OTA or
# diagnostics services, no single-app runtime shell -- SwiftUI owns the run
# loop. The camera bridge stays: watchos_platform.mm answers it with "no camera".
# shellcheck source=/dev/null
source "$GEA_CORE/gea_sources.sh"
export GEA_FW_CXX_SOURCES="$(gea_fw_cxx_sources | grep -vE "/(runtime|services/[a-z_]+)\.cpp\$")"
export GEA_FW_C_SOURCES="$(gea_fw_c_sources)"
export GEA_FW_INCLUDE_DIRS="$(gea_fw_include_flags | sed "s/^-I//")"
APP_ID="${1:-counter-jsx}"
DESTINATION="${2:-simulator}"

if [[ "$DESTINATION" != "simulator" && "$DESTINATION" != "device" ]]; then
  echo "usage: targets/watchos/build-watchos.sh [app-id] [simulator|device]" >&2
  exit 2
fi

APP_INFO="$(node "$GEA_CLI" apps inspect "$APP_ID" --format shell)" || {
  echo "Unknown app id: $APP_ID" >&2
  exit 1
}

IFS=$'\t' read -r APP_ROOT APP_ENTRY APP_RUNTIME APP_DISPLAY_NAME <<< "$APP_INFO"
if [[ "$APP_RUNTIME" != "gea" ]]; then
  echo "watchOS target only supports runtime=gea apps: $APP_ID is runtime=$APP_RUNTIME" >&2
  exit 1
fi
APP_NAME="$(node -e "
  const raw = process.argv[1] || process.argv[2];
  console.log(raw.replace(/(^|[-_\\s])([a-z])/g, (_, p, c) => c.toUpperCase()).replace(/[-_\\s]+/g, ''));
" "$APP_DISPLAY_NAME" "$APP_ID")"
BUNDLE_ID="${GEA_WATCHOS_BUNDLE_IDENTIFIER:-com.gea.watch.${APP_ID//[^A-Za-z0-9]/-}}"
# Output belongs to the app being built, never to this package (see build-ios.sh).
WATCHOS_OUTPUT_ROOT="${GEA_WATCHOS_OUTPUT_DIR:-$BUILD_INVOCATION_CWD/dist/watchos}"
case "$WATCHOS_OUTPUT_ROOT" in
  /*) ;;
  *) WATCHOS_OUTPUT_ROOT="$(pwd -P)/$WATCHOS_OUTPUT_ROOT" ;;
esac
GENERATED_DIR="$WATCHOS_OUTPUT_ROOT/.generated/$APP_ID"
PROJECT_PATH="$WATCHOS_OUTPUT_ROOT/$APP_ID/GeaWatch.xcodeproj"
DERIVED_DATA="$WATCHOS_OUTPUT_ROOT/.derived-data/$APP_ID-$DESTINATION"
CONFIGURATION="${GEA_WATCHOS_CONFIGURATION:-Debug}"
SKIP_LAUNCH="${GEA_WATCHOS_SKIP_LAUNCH:-0}"

mkdir -p "$GENERATED_DIR"

# How many physical pixels one CSS px covers. Apple Watch panels are the same
# class as the ESP32 watch boards (368x448, 410x502 ...), which declare 1.5, so
# an app looks the same size on either. An app overrides it the way the CLI's
# build config reads it: gea.targets.watchos.cssDevicePixelRatio, then
# gea.cssDevicePixelRatio.
CSS_DEVICE_PIXEL_RATIO="${GEA_WATCHOS_CSS_DEVICE_PIXEL_RATIO:-$(node -e '
const gea = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).gea || {}
const target = gea.targets && typeof gea.targets.watchos === "object" ? gea.targets.watchos : {}
const ratio = Number(target.cssDevicePixelRatio || gea.cssDevicePixelRatio || 1.5)
process.stdout.write(String(ratio > 0 ? ratio : 1.5))
' "$APP_ROOT/package.json")}"

# Bake glyph atlases at the layout ratio, and give vw/vh-sized text the
# physical panel sizes of current watches (40mm SE .. 49mm Ultra 3).
build_font_args=(
  --font-device-pixel-ratio "${GEA_WATCHOS_FONT_DEVICE_PIXEL_RATIOS:-$CSS_DEVICE_PIXEL_RATIO}"
  --font-viewport-width "${GEA_WATCHOS_FONT_VIEWPORT_WIDTHS:-324,352,368,374,396,410,416,422}"
  --font-viewport-height "${GEA_WATCHOS_FONT_VIEWPORT_HEIGHTS:-394,430,446,448,484,496,502,514}"
)

# watchOS has no UIView tree for the Apple SDK bindings to drive, so apps are
# compiled without them (no native bridge, no apple-native geatsc plugin).
args=(
  --no-apple-native
  --app-dir "$APP_ROOT"
  --entry "$APP_ENTRY"
  --out-dir "$GENERATED_DIR"
  "${build_font_args[@]}"
)
if [[ -f "$APP_ROOT/watchos/geatsc-native-plugin.mjs" ]]; then
  args+=(--extra-geatsc-plugin "$APP_ROOT/watchos/geatsc-native-plugin.mjs")
fi
node "$GEA_CORE/scripts/build-gea-vite-geatsc.mjs" "${args[@]}"

if [[ ! -f "$GENERATED_DIR/gea_runtime.cpp" ]]; then
  echo "#include \"$GEA_COMPILER/dist/targets/cpp/runtime/runtime.cpp\"" > "$GENERATED_DIR/gea_runtime.cpp"
fi

GEA_CLI_BIN="$GEA_CLI" node "$WATCHOS_DIR/generate-xcode-project.mjs" \
  --app-id "$APP_ID" \
  --app-name "$APP_NAME" \
  --display-name "$APP_DISPLAY_NAME" \
  --bundle-id "$BUNDLE_ID" \
  --css-device-pixel-ratio "$CSS_DEVICE_PIXEL_RATIO" \
  --generated-dir "$GENERATED_DIR" \
  --project-path "$PROJECT_PATH"

# Picks a booted Apple Watch simulator, else a mid-size Series model: the
# 40mm SE is smaller than most gea layouts are drawn for.
pick_simulator_device() {
  local devices_json
  devices_json="$(xcrun simctl list devices available --json 2>/dev/null || true)"
  [[ -z "$devices_json" ]] && return 0
  node -e "
    const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const watches = Object.entries(data.devices || {})
      .filter(([runtime]) => /watchOS/.test(runtime))
      .flatMap(([, list]) => list)
      .filter((d) => d.isAvailable && /^Apple Watch/.test(d.name));
    const preferred = watches.find((d) => d.state === 'Booted') || watches.find((d) => /Series/.test(d.name)) || watches[0];
    if (preferred) console.log(preferred.udid);
  " <<< "$devices_json"
}

show_simulator_device() {
  [[ "${GEA_WATCHOS_OPEN_SIMULATOR:-1}" == "1" ]] || return 0
  # Only a convenience: the device boots, installs and launches without the
  # GUI. Xcode 27 replaced Simulator.app with DeviceHub.app (bundle id
  # com.apple.dt.Devices), which shows every booted simulator.
  /usr/bin/open -a Simulator --args -CurrentDeviceUDID "$1" 2>/dev/null ||
    /usr/bin/open -b com.apple.dt.Devices 2>/dev/null ||
    echo "Could not open Simulator.app or DeviceHub.app; the simulator runs without a window." >&2
}

SDK="watchsimulator"
XCODE_DESTINATION="${GEA_WATCHOS_SIMULATOR_DESTINATION:-generic/platform=watchOS Simulator}"
SIMULATOR_DEVICE_ID="${GEA_WATCHOS_SIMULATOR_UDID:-}"
EXTRA_BUILD_SETTINGS=()
EXTRA_XCODEBUILD_ARGS=()
WATCH_DEVICE_ID="${GEA_WATCHOS_DEVICE_ID:-}"
if [[ "$DESTINATION" == "simulator" && "$SKIP_LAUNCH" != "1" && -z "$SIMULATOR_DEVICE_ID" ]]; then
  SIMULATOR_DEVICE_ID="$(pick_simulator_device)"
  if [[ -z "$SIMULATOR_DEVICE_ID" ]]; then
    echo "No available Apple Watch simulator found. Add one in Xcode > Window > Devices and Simulators." >&2
    exit 1
  fi
fi
if [[ "$DESTINATION" == "simulator" && -n "$SIMULATOR_DEVICE_ID" && -z "${GEA_WATCHOS_SIMULATOR_DESTINATION:-}" ]]; then
  XCODE_DESTINATION="platform=watchOS Simulator,id=$SIMULATOR_DEVICE_ID"
fi
if [[ "$DESTINATION" == "device" ]]; then
  SDK="watchos"
  XCODE_DESTINATION="${GEA_WATCHOS_DEVICE_DESTINATION:-generic/platform=watchOS}"
  # A watch is reached through its paired iPhone, so there is no reliable way
  # to pick one automatically: name it with GEA_WATCHOS_DEVICE_ID (the
  # identifier `xcrun devicectl list devices` prints) to install and launch.
  if [[ -z "$WATCH_DEVICE_ID" && "$SKIP_LAUNCH" != "1" ]]; then
    echo "Set GEA_WATCHOS_DEVICE_ID to the watch's identifier from 'xcrun devicectl list devices' to install and launch," >&2
    echo "or GEA_WATCHOS_SKIP_LAUNCH=1 to only build." >&2
    exit 1
  fi
  DEVELOPMENT_TEAM="${GEA_WATCHOS_DEVELOPMENT_TEAM:-${GEA_IOS_DEVELOPMENT_TEAM:-}}"
  if [[ -z "$DEVELOPMENT_TEAM" && "$SKIP_LAUNCH" != "1" ]]; then
    if DEVELOPMENT_TEAM="$(node "$ROOT_DIR/targets/ios/detect-development-team.mjs")"; then
      echo "Using Xcode development team $DEVELOPMENT_TEAM. Override with GEA_WATCHOS_DEVELOPMENT_TEAM." >&2
    else
      DEVELOPMENT_TEAM=""
    fi
  fi
  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    if [[ "$SKIP_LAUNCH" != "1" ]]; then
      echo "Device builds require GEA_WATCHOS_DEVELOPMENT_TEAM for Xcode automatic signing." >&2
      exit 1
    fi
    echo "GEA_WATCHOS_DEVELOPMENT_TEAM is not set; building an unsigned watchos binary." >&2
    EXTRA_BUILD_SETTINGS+=("CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=")
  else
    EXTRA_BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "CODE_SIGN_STYLE=Automatic")
    if [[ "${GEA_WATCHOS_ALLOW_PROVISIONING_UPDATES:-1}" == "1" ]]; then
      EXTRA_XCODEBUILD_ARGS+=("-allowProvisioningUpdates")
    fi
  fi
fi

xcodebuild \
  ${EXTRA_XCODEBUILD_ARGS[@]+"${EXTRA_XCODEBUILD_ARGS[@]}"} \
  -project "$PROJECT_PATH" \
  -scheme GeaWatch \
  -configuration "$CONFIGURATION" \
  -sdk "$SDK" \
  -destination "$XCODE_DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  ${EXTRA_BUILD_SETTINGS[@]+"${EXTRA_BUILD_SETTINGS[@]}"} \
  build

APP_PRODUCT="$DERIVED_DATA/Build/Products/$CONFIGURATION-$SDK/$APP_NAME.app"
echo "Built $APP_PRODUCT"

[[ "$SKIP_LAUNCH" == "1" ]] && exit 0

if [[ "$DESTINATION" == "simulator" ]]; then
  show_simulator_device "$SIMULATOR_DEVICE_ID"
  xcrun simctl boot "$SIMULATOR_DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_DEVICE_ID" -b >/dev/null || true
  xcrun simctl install "$SIMULATOR_DEVICE_ID" "$APP_PRODUCT"
  xcrun simctl launch "$SIMULATOR_DEVICE_ID" "$BUNDLE_ID"
else
  xcrun devicectl --timeout "${GEA_WATCHOS_DEVICECTL_TIMEOUT:-120}" device install app --device "$WATCH_DEVICE_ID" "$APP_PRODUCT"
  xcrun devicectl --timeout "${GEA_WATCHOS_DEVICECTL_TIMEOUT:-120}" device process launch --terminate-existing --device "$WATCH_DEVICE_ID" "$BUNDLE_ID"
fi

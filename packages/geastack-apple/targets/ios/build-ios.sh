#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/targets/ios"

# The project is the directory this script was started in -- `gea build
# --target ios` spawns it with the app's own folder as cwd, and a direct run is
# made from the app folder. Captured once, before anything can move. Every
# nested `gea` call inherits the same cwd and resolves the same project, so
# none carry --project.
BUILD_INVOCATION_CWD="$(pwd -P)"

# Resolve the gea framework through npm plus the shared manifest, the same way
# build-macos.sh does. `apple` is a native npm package whose @geastack/* deps
# npm HOISTS to the app's node_modules, one or more levels above this package,
# while a linked checkout has them under its own. Looking one level below this
# package -- what this script did before -- finds nothing in either installed
# layout, so walk the node_modules chain from the app first, then from here.
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
  for start in "${2:-$BUILD_INVOCATION_CWD}" "${2:-$ROOT_DIR}"; do
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
# An app that installs @geastack/apple gets the plugin from node_modules; inside
# this repository it is a sibling package that nothing links, so name it there.
GEA_APPLE_NATIVE_PLUGIN="$(resolve_gea_package @geastack/geatsc-plugin-apple-native)"
if [[ -z "$GEA_APPLE_NATIVE_PLUGIN" && -d "$ROOT_DIR/../geatsc-plugin-apple-native" ]]; then
  GEA_APPLE_NATIVE_PLUGIN="$(cd "$ROOT_DIR/../geatsc-plugin-apple-native" && pwd)"
fi
[ -n "$GEA_APPLE_NATIVE_PLUGIN" ] && [ -f "$GEA_APPLE_NATIVE_PLUGIN/dist/index.js" ] || { echo "Cannot resolve @geastack/geatsc-plugin-apple-native from $BUILD_INVOCATION_CWD" >&2; exit 1; }
GEA_HOST_DIR="${GEA_HOST_DIR:-$GEA_CORE/../host}"
GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-$GEA_CORE/../engine}"
GEA_ELEMENTS_DIR="${GEA_ELEMENTS_DIR:-$GEA_CORE/../elements}"
GEA_GEAOS_PACKAGE_DIR="${GEA_GEAOS_PACKAGE_DIR:-$GEA_CORE/../geaos}"
# The source manifest reads these from the ENVIRONMENT: gea_sources.sh is a
# front end for gea_sources.mjs, which runs as a child process. A plain shell
# variable never reaches it and it reports "<name> unset" while the include
# roots come back empty.
export GEA_CORE GEA_HOST_DIR GEA_ENGINE_DIR GEA_ELEMENTS_DIR GEA_GEAOS_PACKAGE_DIR
# This script IS @geastack/apple, so the generator must bind against this
# working copy rather than whatever installed copy it would resolve from the app.
export GEA_APPLE_ROOT="$ROOT_DIR"
# Prefer an explicit override, then the package the app installed, then gea on PATH.
GEA_CLI="${GEA_CLI_BIN:-}"
if [[ -z "$GEA_CLI" ]]; then
  GEA_CLI="$(node -e 'process.stdout.write(require("path").join(process.argv[1], "bin", "gea.mjs"))' "$(resolve_gea_package @geastack/cli)" 2>/dev/null || true)"
  if [[ ! -f "$GEA_CLI" ]]; then
    GEA_CLI="$(command -v gea || true)"
  fi
fi
[ -n "$GEA_CLI" ] && [ -f "$GEA_CLI" ] || { echo "Cannot locate GeaStack CLI — set GEA_CLI_BIN to gea.mjs, install @geastack/cli locally, or add gea to PATH" >&2; exit 1; }

# Framework sources/includes from the shared manifest (iOS keeps camera — ios_camera.mm
# provides it — but has no OTA/diagnostics services or single-app runtime
# shell, so exclude those). generate-xcode-project.mjs consumes these.
# shellcheck source=/dev/null
source "$GEA_CORE/gea_sources.sh"
export GEA_FW_CXX_SOURCES="$(gea_fw_cxx_sources | grep -vE "/(runtime|services/[a-z_]+)\.cpp\$")"
export GEA_FW_C_SOURCES="$(gea_fw_c_sources)"
export GEA_FW_INCLUDE_DIRS="$(gea_fw_include_flags | sed "s/^-I//")"
APP_ID="${1:-bouncing-balls-jsx}"
DESTINATION="${2:-simulator}"

if [[ "$DESTINATION" != "simulator" && "$DESTINATION" != "device" ]]; then
  echo "usage: targets/ios/build-ios.sh [app-id] [simulator|device]" >&2
  exit 2
fi

APP_INFO="$(node "$GEA_CLI" apps inspect "$APP_ID" --format shell)" || {
  echo "Unknown app id: $APP_ID" >&2
  exit 1
}

IFS=$'\t' read -r APP_ROOT APP_ENTRY APP_RUNTIME APP_DISPLAY_NAME <<< "$APP_INFO"
if [[ "$APP_RUNTIME" != "gea" ]]; then
  echo "iOS target only supports runtime=gea apps for now: $APP_ID is runtime=$APP_RUNTIME" >&2
  exit 1
fi
APP_NAME="$(node -e "
  const raw = process.argv[1] || process.argv[2];
  console.log(raw.replace(/(^|[-_\\s])([a-z])/g, (_, p, c) => c.toUpperCase()).replace(/[-_\\s]+/g, ''));
" "$APP_DISPLAY_NAME" "$APP_ID")"
BUNDLE_ID="${GEA_IOS_BUNDLE_IDENTIFIER:-com.gea.${APP_ID//[^A-Za-z0-9]/-}}"
# Build output belongs to the PROJECT being built, never to this package.
# IOS_DIR lives inside @geastack/apple, which for an app that installs the
# package means node_modules -- a directory nobody opens and npm wipes on the
# next install. The invocation directory is the app the CLI resolved, so output
# sources, the Xcode project and DerivedData land next to the app's source.
# GEA_IOS_OUTPUT_DIR overrides the root for a caller that wants it elsewhere.
IOS_OUTPUT_ROOT="${GEA_IOS_OUTPUT_DIR:-$BUILD_INVOCATION_CWD/dist/ios}"
case "$IOS_OUTPUT_ROOT" in
  /*) ;;
  *) IOS_OUTPUT_ROOT="$(pwd -P)/$IOS_OUTPUT_ROOT" ;;
esac
GENERATED_DIR="$IOS_OUTPUT_ROOT/.generated/$APP_ID"
PROJECT_PATH="$IOS_OUTPUT_ROOT/$APP_ID/GeaIos.xcodeproj"
DERIVED_DATA="$IOS_OUTPUT_ROOT/.derived-data/$APP_ID-$DESTINATION"
CONFIGURATION="${GEA_IOS_CONFIGURATION:-Debug}"
SKIP_LAUNCH="${GEA_IOS_SKIP_LAUNCH:-0}"

mkdir -p "$GENERATED_DIR"

build_font_args=(
  --font-device-pixel-ratio "${GEA_IOS_FONT_DEVICE_PIXEL_RATIOS:-2,3}"
  --font-viewport-width "${GEA_IOS_FONT_VIEWPORT_WIDTHS:-750,828,1125,1170,1290}"
)

generate_app() {
  local app_id="$1"
  local out_dir="$2"
  local info
  local root
  local entry
  local runtime
  info="$(node "$GEA_CLI" apps inspect "$app_id" --format shell)" || return 1
  IFS=$'\t' read -r root entry runtime _name <<< "$info"
  if [[ "$runtime" != "gea" ]]; then
    echo "iOS target only supports runtime=gea apps: $app_id is runtime=$runtime" >&2
    return 1
  fi
  local args=(
    # Which platform's SDK the bridge metadata describes. It defaults to the
    # empty string, meaning "no platform filter", and the filter is not
    # cosmetic: `writeAppleNativeMetadata` strips the off-platform frameworks'
    # functions and members, so an unfiltered metadata declares AppKit's
    # `installRootView` alongside UIKit's in an iOS app's bridge -- a free
    # function no iOS target defines. `build-macos.sh` passes `macos` for the
    # same reason; iOS was simply never given its half.
    --apple-platform ios
    # The plugin is resolved above the way build-macos.sh resolves it: from the
    # app's node_modules, or the sibling package inside this repository.
    --geatsc-apple-native-plugin "$GEA_APPLE_NATIVE_PLUGIN/dist/index.js"
    --app-dir "$root"
    --entry "$entry"
    --out-dir "$out_dir"
    "${build_font_args[@]}"
  )
  local native_plugin="$root/ios/geatsc-native-plugin.mjs"
  if [[ -f "$native_plugin" ]]; then
    args+=(--extra-geatsc-plugin "$native_plugin")
  fi
  node "$GEA_CORE/scripts/build-gea-vite-geatsc.mjs" "${args[@]}"
}

pick_simulator_device() {
  local devices_json
  devices_json="$(xcrun simctl list devices available --json 2>/dev/null || true)"
  if [[ -z "$devices_json" ]]; then
    return 0
  fi
  node -e "
    const fs = require('fs');
    const input = fs.readFileSync(0, 'utf8');
    if (!input.trim()) process.exit(0);
    const data = JSON.parse(input);
    const devices = Object.values(data.devices || {}).flat();
    const iphones = devices.filter((d) => d.isAvailable && /^iPhone/.test(d.name));
    const booted = iphones.find((d) => d.state === 'Booted');
    const preferred = booted || iphones[iphones.length - 1];
    if (preferred) console.log(preferred.udid);
  " <<< "$devices_json"
}

# Build an xcodebuild -destination string for a simulator UDID using its
# name + OS version. The "name=…,OS=…" form is resolved directly by xcodebuild,
# unlike "id=<udid>", which must match the scheme's destination enumeration —
# and that enumeration is intermittently empty when a connected real iPhone
# lacks its device-support platform, making id-matching flaky.
sim_destination_for_udid() {
  local udid="$1"
  local devices_json
  devices_json="$(xcrun simctl list devices available --json 2>/dev/null || true)"
  [[ -z "$devices_json" ]] && return 0
  node -e "
    const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const want = process.argv[1];
    for (const [runtime, list] of Object.entries(data.devices || {})) {
      for (const d of list) {
        if (d.udid === want) {
          const m = runtime.match(/iOS-(\d+)-(\d+)/);
          const os = m ? m[1] + '.' + m[2] : '';
          process.stdout.write('platform=iOS Simulator,name=' + d.name + (os ? ',OS=' + os : ''));
          process.exit(0);
        }
      }
    }
  " "$udid" <<< "$devices_json"
}

show_simulator_device() {
  local udid="$1"
  if [[ "${GEA_IOS_OPEN_SIMULATOR:-1}" != "1" ]]; then
    return 0
  fi
  /usr/bin/open -a Simulator --args -CurrentDeviceUDID "$udid"
}

pick_ios_device() {
  local output_json
  output_json="$(mktemp "${TMPDIR:-/tmp}/gea-ios-devices.XXXXXX.json")"
  if ! xcrun devicectl list devices --timeout "${GEA_IOS_DEVICECTL_TIMEOUT:-30}" --json-output "$output_json" >/dev/null; then
    rm -f "$output_json"
    return 0
  fi
  node -e "
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    const devices = data.result?.devices || [];
    const usable = devices.filter((device) => {
      const hardware = device.hardwareProperties || {};
      const props = device.deviceProperties || {};
      const capabilities = device.capabilities || [];
      const features = new Set(capabilities.map((capability) => capability.featureIdentifier));
      return hardware.platform === 'iOS' &&
        hardware.deviceType === 'iPhone' &&
        props.developerModeStatus === 'enabled' &&
        device.connectionProperties?.tunnelState === 'connected' &&
        features.has('com.apple.coredevice.feature.installapp') &&
        features.has('com.apple.coredevice.feature.launchapplication');
    });
    usable.sort((a, b) => {
      const aDate = Date.parse(a.connectionProperties?.lastConnectionDate || '') || 0;
      const bDate = Date.parse(b.connectionProperties?.lastConnectionDate || '') || 0;
      return aDate - bDate;
    });
    const picked = usable[usable.length - 1];
    if (picked) console.log(picked.identifier || picked.hardwareProperties?.udid || picked.deviceProperties?.name || '');
  " "$output_json"
  rm -f "$output_json"
}

generate_app "$APP_ID" "$GENERATED_DIR"

if [[ ! -f "$GENERATED_DIR/gea_runtime.cpp" ]]; then
  echo "#include \"$GEA_COMPILER/dist/targets/cpp/runtime/runtime.cpp\"" > "$GENERATED_DIR/gea_runtime.cpp"
fi

GEA_CLI_BIN="$GEA_CLI" node "$IOS_DIR/generate-xcode-project.mjs" \
  --app-id "$APP_ID" \
  --app-name "$APP_NAME" \
  --bundle-id "$BUNDLE_ID" \
  --generated-dir "$GENERATED_DIR" \
  --project-path "$PROJECT_PATH"

SDK="iphonesimulator"
SIMULATOR_DEVICE_ID="${GEA_IOS_SIMULATOR_UDID:-}"
XCODE_DESTINATION="${GEA_IOS_SIMULATOR_DESTINATION:-generic/platform=iOS Simulator}"
if [[ "$DESTINATION" == "simulator" ]]; then
  if [[ "$SKIP_LAUNCH" == "1" ]]; then
    XCODE_DESTINATION="${GEA_IOS_SIMULATOR_DESTINATION:-generic/platform=iOS Simulator}"
  else
    if [[ -z "$SIMULATOR_DEVICE_ID" ]]; then
      SIMULATOR_DEVICE_ID="$(pick_simulator_device)"
    fi
    if [[ -z "$SIMULATOR_DEVICE_ID" ]]; then
      echo "No available iPhone simulator found." >&2
      exit 1
    fi
    # Resolve a name+OS destination (robust against the poisoned enumeration that
    # a connected real iPhone causes); fall back to id= if the lookup fails.
    XCODE_DESTINATION="${GEA_IOS_SIMULATOR_DESTINATION:-}"
    if [[ -z "$XCODE_DESTINATION" ]]; then
      XCODE_DESTINATION="$(sim_destination_for_udid "$SIMULATOR_DEVICE_ID")"
      [[ -z "$XCODE_DESTINATION" ]] && XCODE_DESTINATION="platform=iOS Simulator,id=$SIMULATOR_DEVICE_ID"
    fi
  fi
fi
EXTRA_BUILD_SETTINGS=()
EXTRA_XCODEBUILD_ARGS=()
IOS_DEVICE_ID="${GEA_IOS_DEVICE_ID:-}"
if [[ "$DESTINATION" == "device" ]]; then
  SDK="iphoneos"
  XCODE_DESTINATION="${GEA_IOS_DEVICE_DESTINATION:-generic/platform=iOS}"
  if [[ -z "$IOS_DEVICE_ID" && "$SKIP_LAUNCH" != "1" ]]; then
    IOS_DEVICE_ID="$(pick_ios_device)"
    if [[ -n "$IOS_DEVICE_ID" ]]; then
      echo "Using iOS device $IOS_DEVICE_ID. Override with GEA_IOS_DEVICE_ID." >&2
    fi
  fi
  if [[ -z "$IOS_DEVICE_ID" && "$SKIP_LAUNCH" != "1" ]]; then
    echo "No available iPhone device found for install or launch." >&2
    echo "Connect an iPhone with Developer Mode enabled, or set GEA_IOS_DEVICE_ID." >&2
    exit 1
  fi
  DEVELOPMENT_TEAM="${GEA_IOS_DEVELOPMENT_TEAM:-}"
  if [[ -z "$DEVELOPMENT_TEAM" && "$SKIP_LAUNCH" != "1" ]]; then
    if DEVELOPMENT_TEAM="$(node "$IOS_DIR/detect-development-team.mjs")"; then
      echo "Using Xcode development team $DEVELOPMENT_TEAM. Override with GEA_IOS_DEVELOPMENT_TEAM." >&2
    else
      DEVELOPMENT_TEAM=""
    fi
  fi
  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    if [[ "$SKIP_LAUNCH" != "1" ]]; then
      echo "Device builds require GEA_IOS_DEVELOPMENT_TEAM for Xcode automatic signing." >&2
      echo "The script also checks Xcode preferences and installed provisioning profiles, but no unambiguous team was found." >&2
      echo "Example: GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 targets/ios/build-ios.sh $APP_ID device" >&2
      exit 1
    fi
    echo "GEA_IOS_DEVELOPMENT_TEAM is not set; building an unsigned iphoneos binary." >&2
    echo "Set GEA_IOS_DEVELOPMENT_TEAM to install or launch on an iPhone." >&2
    EXTRA_BUILD_SETTINGS+=("CODE_SIGNING_ALLOWED=NO")
    EXTRA_BUILD_SETTINGS+=("CODE_SIGNING_REQUIRED=NO")
    EXTRA_BUILD_SETTINGS+=("CODE_SIGN_IDENTITY=")
  else
    EXTRA_BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
    EXTRA_BUILD_SETTINGS+=("CODE_SIGN_STYLE=Automatic")
    ALLOW_PROVISIONING_UPDATES="${GEA_IOS_ALLOW_PROVISIONING_UPDATES:-}"
    if [[ -z "$ALLOW_PROVISIONING_UPDATES" && "$SKIP_LAUNCH" != "1" ]]; then
      ALLOW_PROVISIONING_UPDATES="1"
    fi
    if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
      echo "Allowing Xcode to create or update iOS provisioning profiles." >&2
      echo "Set GEA_IOS_ALLOW_PROVISIONING_UPDATES=0 to disable this." >&2
      EXTRA_XCODEBUILD_ARGS+=("-allowProvisioningUpdates")
    fi
  fi
fi

# xcodebuild's destination resolution is intermittently empty when a connected
# real iPhone lacks its device-support platform — even an explicit simulator
# destination then fails to match. Retry on that specific flake (re-settling the
# sim first); any other failure breaks out immediately.
XCODEBUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/gea-ios-xcodebuild.XXXXXX.log")"
XCODEBUILD_ATTEMPTS="${GEA_IOS_BUILD_ATTEMPTS:-3}"
xcodebuild_status=1
for ((xcodebuild_attempt = 1; xcodebuild_attempt <= XCODEBUILD_ATTEMPTS; xcodebuild_attempt++)); do
  set +e
  xcodebuild \
    ${EXTRA_XCODEBUILD_ARGS[@]+"${EXTRA_XCODEBUILD_ARGS[@]}"} \
    -project "$PROJECT_PATH" \
    -scheme GeaIos \
    -configuration "$CONFIGURATION" \
    -sdk "$SDK" \
    -destination "$XCODE_DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    ${EXTRA_BUILD_SETTINGS[@]+"${EXTRA_BUILD_SETTINGS[@]}"} \
    build 2>&1 | tee "$XCODEBUILD_LOG"
  xcodebuild_status=${PIPESTATUS[0]}
  set -e
  [[ $xcodebuild_status -eq 0 ]] && break
  if [[ "$DESTINATION" == "simulator" ]] && grep -q "Unable to find a destination" "$XCODEBUILD_LOG"; then
    echo "xcodebuild could not resolve the simulator destination (flaky with a connected device); re-settling sim and retrying ($xcodebuild_attempt/$XCODEBUILD_ATTEMPTS)." >&2
    if [[ -n "$SIMULATOR_DEVICE_ID" ]]; then
      xcrun simctl boot "$SIMULATOR_DEVICE_ID" >/dev/null 2>&1 || true
      xcrun simctl bootstatus "$SIMULATOR_DEVICE_ID" -b >/dev/null 2>&1 || true
    fi
    continue
  fi
  break
done
rm -f "$XCODEBUILD_LOG"
[[ $xcodebuild_status -eq 0 ]] || exit "$xcodebuild_status"

APP_PRODUCT="$DERIVED_DATA/Build/Products/$CONFIGURATION-$SDK/$APP_NAME.app"
echo "Built $APP_PRODUCT"

if [[ "$DESTINATION" == "simulator" && "$SKIP_LAUNCH" != "1" ]]; then
  if [[ -z "$SIMULATOR_DEVICE_ID" ]]; then
    SIMULATOR_DEVICE_ID="$(pick_simulator_device)"
  fi
  if [[ -z "$SIMULATOR_DEVICE_ID" ]]; then
    echo "No available iPhone simulator found; build succeeded without launch." >&2
    exit 0
  fi
  show_simulator_device "$SIMULATOR_DEVICE_ID"
  xcrun simctl boot "$SIMULATOR_DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_DEVICE_ID" -b >/dev/null || true
  xcrun simctl install "$SIMULATOR_DEVICE_ID" "$APP_PRODUCT"
  xcrun simctl launch "$SIMULATOR_DEVICE_ID" "$BUNDLE_ID"
fi

if [[ "$DESTINATION" == "device" && "$SKIP_LAUNCH" != "1" ]]; then
  if [[ -z "$IOS_DEVICE_ID" ]]; then
    IOS_DEVICE_ID="$(pick_ios_device)"
  fi
  if [[ -z "$IOS_DEVICE_ID" ]]; then
    echo "No available iPhone device found; build succeeded without launch." >&2
    exit 0
  fi
  xcrun devicectl --timeout "${GEA_IOS_DEVICECTL_TIMEOUT:-60}" device install app --device "$IOS_DEVICE_ID" "$APP_PRODUCT"
  xcrun devicectl --timeout "${GEA_IOS_DEVICECTL_TIMEOUT:-60}" device process launch --terminate-existing --activate --device "$IOS_DEVICE_ID" "$BUNDLE_ID"
fi

#!/usr/bin/env bash
set -euo pipefail

MACOS_TIMINGS="${GEA_MACOS_TIMINGS:-0}"
MACOS_TIMING_START_US=0
MACOS_TIMING_LAST_US=0
timing_now_us() {
  perl -MTime::HiRes=time -e 'printf "%.0f", time() * 1000000'
}
timing_mark() {
  [[ "$MACOS_TIMINGS" == "1" ]] || return 0
  local label="$1"
  local now delta total
  now="$(timing_now_us)"
  delta=$((now - MACOS_TIMING_LAST_US))
  total=$((now - MACOS_TIMING_START_US))
  printf '[macos timing] %-18s %d.%03ds (total %d.%03ds)\n' \
    "$label" $((delta / 1000000)) $(((delta / 1000) % 1000)) \
    $((total / 1000000)) $(((total / 1000) % 1000)) >&2
  MACOS_TIMING_LAST_US="$now"
}
if [[ "$MACOS_TIMINGS" == "1" ]]; then
  MACOS_TIMING_START_US="$(timing_now_us)"
  MACOS_TIMING_LAST_US="$MACOS_TIMING_START_US"
fi

MACOS_PIPELINE_CACHE="${GEA_MACOS_PIPELINE_CACHE:-1}"
case "$MACOS_PIPELINE_CACHE" in
  0|1) ;;
  *) echo "GEA_MACOS_PIPELINE_CACHE must be 0 or 1" >&2; exit 1 ;;
esac

replace_content_stable() {
  local destination="$1"
  local temporary="$2"
  if [[ "$MACOS_PIPELINE_CACHE" == "1" && -f "$destination" ]] && cmp -s "$temporary" "$destination"; then
    rm -f "$temporary"
    return 1
  fi
  mkdir -p "$(dirname "$destination")"
  mv "$temporary" "$destination"
  return 0
}

configure_macos_output_namespace() {
  local app_id="$1"
  local output_tag="$2"
  if [[ -z "$output_tag" ]]; then
    MACOS_OUTPUT_SUBPATH="$app_id"
    MACOS_BUILD_LABEL="$app_id"
    return 0
  fi
  if [[ ! "$output_tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || (( ${#output_tag} > 64 )); then
    echo "Invalid macOS output tag '$output_tag' (use 1-64 characters: leading alphanumeric, then alphanumeric/._-)" >&2
    return 1
  fi
  # Keep app ids as siblings inside a tag. macos_app_platform.mm walks from
  # <namespace>/<app>/<Name>.app to <namespace> and appends the target app id.
  MACOS_OUTPUT_SUBPATH=".namespaces/$output_tag/$app_id"
  MACOS_BUILD_LABEL="$app_id@$output_tag"
}

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_INVOCATION_CWD="$(pwd -P)"
# This script IS @geastack/apple, so the generator must bind against this
# working copy rather than whatever installed copy it would resolve from the app.
export GEA_APPLE_ROOT="$ROOT_DIR"
MACOS_HARD_MUTE_GATE="${GEA_MACOS_HARD_MUTE_GATE:-}"
MACOS_HARD_MUTE_SOURCE="${GEA_MACOS_HARD_MUTE_SOURCE:-}"
if [[ -n "$MACOS_HARD_MUTE_GATE" && -z "$MACOS_HARD_MUTE_SOURCE" ]] || \
   [[ -z "$MACOS_HARD_MUTE_GATE" && -n "$MACOS_HARD_MUTE_SOURCE" ]]; then
  echo "GEA_MACOS_HARD_MUTE_GATE and GEA_MACOS_HARD_MUTE_SOURCE must be set together" >&2
  exit 2
fi
APP_ID="hello"
if (( $# > 0 )) && [[ "$1" != --* ]]; then
  APP_ID="$1"
  shift
fi
MACOS_OUTPUT_TAG="${GEA_MACOS_OUTPUT_TAG:-}"
while (( $# > 0 )); do
  case "$1" in
    --output-tag)
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        echo "--output-tag requires a non-empty value" >&2
        exit 2
      fi
      MACOS_OUTPUT_TAG="$2"
      shift 2
      ;;
    --output-tag=*)
      MACOS_OUTPUT_TAG="${1#--output-tag=}"
      if [[ -z "$MACOS_OUTPUT_TAG" ]]; then
        echo "--output-tag requires a non-empty value" >&2
        exit 2
      fi
      shift
      ;;
    *)
      echo "Unknown macOS build argument: $1" >&2
      exit 2
      ;;
  esac
done
MACOS_OUTPUT_SUBPATH=""
MACOS_BUILD_LABEL=""
configure_macos_output_namespace "$APP_ID" "$MACOS_OUTPUT_TAG" || exit 2
# shellcheck source=/dev/null
source "$ROOT_DIR/targets/macos/build-child-lifecycle.sh"

# Resolve the gea framework through npm plus the shared manifest. `apple` is a
# native npm package whose @geastack/* deps npm installs into node_modules.
# Framework C/C++ sources + include roots come from @geastack/core/gea_sources.sh
# (shared with web/esp32).
# Walk the node_modules chain rather than looking one level down. This target
# ships inside @geastack/apple, so when an app installs it the siblings it needs
# are hoisted to the APP's node_modules, one or more levels above this package,
# and a linked checkout has them under its own instead. One resolver answers
# both without a layout assumption.
# Two starting points, the APP first. ROOT_DIR is this script's own location
# with every symlink already resolved by `cd`, so an app that depends on
# @geastack/apple through a LINK -- a checkout of this repository beside the
# app, which is how a three.js app installs it -- sends the walk back into this
# repository, where the sibling packages are not under any node_modules and
# the chain up to the app's own is gone. The invocation directory IS the app
# (`gea build` spawns this script with the app root as cwd), and that is where
# npm put the siblings, so ask there first and keep ROOT_DIR for an app that
# genuinely contains this package.
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
GEA_APPLE_NATIVE_PLUGIN="$(resolve_gea_package @geastack/geatsc-plugin-apple-native)"
# An app that installs @geastack/apple gets the plugin from node_modules; inside
# this repository it is a sibling package that nothing links, so name it there.
if [[ -z "$GEA_APPLE_NATIVE_PLUGIN" && -d "$ROOT_DIR/../geatsc-plugin-apple-native" ]]; then
  GEA_APPLE_NATIVE_PLUGIN="$(cd "$ROOT_DIR/../geatsc-plugin-apple-native" && pwd)"
fi
[ -n "$GEA_APPLE_NATIVE_PLUGIN" ] && [ -f "$GEA_APPLE_NATIVE_PLUGIN/dist/index.js" ] || { echo "Cannot resolve @geastack/geatsc-plugin-apple-native" >&2; exit 1; }
GEA_COMPILER="$(resolve_gea_package @geastack/compiler)"
GEA_PLUGIN="$(resolve_gea_package @geastack/geatsc-plugin-gea)"
[ -n "$GEA_CORE" ] && [ -f "$GEA_CORE/package.json" ] || { echo "Cannot resolve @geastack/core via node_modules — run 'npm install' in $ROOT_DIR" >&2; exit 1; }
GEA_HOST_DIR="${GEA_HOST_DIR:-$GEA_CORE/../host}"
GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-$GEA_CORE/../engine}"
GEA_ELEMENTS_DIR="${GEA_ELEMENTS_DIR:-$GEA_CORE/../elements}"
GEA_GEAOS_PACKAGE_DIR="${GEA_GEAOS_PACKAGE_DIR:-$GEA_CORE/../geaos}"
GEA_ENGINE="$GEA_ENGINE_DIR"
GEA_GEAOS="$GEA_GEAOS_PACKAGE_DIR"
# The source manifest reads these from the ENVIRONMENT: gea_sources.sh is now a
# front end for gea_sources.mjs, which CMake has to read on Windows where there
# is no bash, so it runs as a child process. A plain shell variable never
# reaches it, and the include roots come back empty -- every framework header
# (app.h, display.h, pixel.h) then goes missing at the first compile.
export GEA_CORE GEA_HOST_DIR GEA_ENGINE_DIR GEA_ELEMENTS_DIR GEA_GEAOS_PACKAGE_DIR
# Shared component CSS (and the @font-face files it references). This was one
# `lib/gea-embedded/components` tree before the split; each package that ships
# components now carries its own, so both have to be named or the bundle
# silently loses whichever is missed -- the walk below and sync-resources both
# skip a directory that is not there without saying so.
GEA_SHARED_COMPONENT_DIRS=("$GEA_ENGINE_DIR/components" "$GEA_ELEMENTS_DIR/components")
# The project is the directory this script was started in. `gea build` spawns it
# with the app's own folder as cwd, and a direct run is made from the app folder
# too, so there is nothing to pass and nothing to guess: BUILD_INVOCATION_CWD
# (captured above, before anything can move) is the whole answer. Every nested
# `gea` call inherits the same cwd and resolves the same project, which is why
# none of them carry --project.
# shellcheck source=/dev/null
source "$GEA_CORE/gea_sources.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/targets/macos/heavy-build-lock.sh"
# Prefer an explicit override, then the local package, then gea on PATH.
GEA_CLI="${GEA_CLI_BIN:-}"
if [[ -z "$GEA_CLI" ]]; then
  GEA_CLI="$(node -e 'process.stdout.write(require("path").join(process.argv[1], "bin", "gea.mjs"))' "$(resolve_gea_package @geastack/cli)" 2>/dev/null || true)"
  if [[ ! -f "$GEA_CLI" ]]; then
    GEA_CLI="$(command -v gea || true)"
  fi
fi
[ -n "$GEA_CLI" ] && [ -f "$GEA_CLI" ] || { echo "Cannot locate GeaStack CLI — set GEA_CLI_BIN to gea.mjs, install @geastack/cli locally, or add gea to PATH" >&2; exit 1; }
# Opt-in benchmark serialization across concurrent builds. It belongs beside the
# apps being built, not beside this package -- installed under node_modules, a
# package-relative path would put every project's lock in a different tree.
HEAVY_BUILD_LOCK_PATH="${GEA_HEAVY_BUILD_LOCK_PATH:-$BUILD_INVOCATION_CWD/.gea-heavy-build.lock}"
case "$HEAVY_BUILD_LOCK_PATH" in
  /*) ;;
  *) HEAVY_BUILD_LOCK_PATH="$(pwd)/$HEAVY_BUILD_LOCK_PATH" ;;
esac

APP_META="$(node "$GEA_CLI" apps inspect "$APP_ID" --format shell 2>/dev/null || true)"
if [[ -n "$APP_META" ]]; then
  IFS=$'\t' read -r _APP_ROOT _APP_ENTRY _APP_RUNTIME APP_NAME < <(printf "%s\n" "$APP_META")
else
  APP_NAME="$(echo "$APP_ID" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
fi
APP_META_CACHE_IDS=("$APP_ID")
APP_META_CACHE_VALUES=("$APP_META")
RESOLVED_APP_META="$APP_META"

# Build output belongs to the PROJECT being built, never to this package.
# ROOT_DIR is @geastack/apple's own directory, which for every app that
# installs the package is inside its node_modules -- so writing the bundle,
# the objects and the generated C++ there buried the build in a directory
# nobody opens, that npm wipes on the next install, and that several projects
# sharing one hoisted copy of the package would write to at the same time.
# The invocation directory is the app the CLI resolved (its own folder), so output
# lands next to the app's source as `dist/macos/<app-id>/<Name>.app`.
# GEA_MACOS_OUTPUT_DIR overrides the root for a caller that wants it elsewhere.
MACOS_OUTPUT_ROOT="${GEA_MACOS_OUTPUT_DIR:-$BUILD_INVOCATION_CWD/dist/macos}"
case "$MACOS_OUTPUT_ROOT" in
  /*) ;;
  *) MACOS_OUTPUT_ROOT="$BUILD_INVOCATION_CWD/$MACOS_OUTPUT_ROOT" ;;
esac
DIST_DIR="$MACOS_OUTPUT_ROOT/$MACOS_OUTPUT_SUBPATH"
BUILD_DIR="$DIST_DIR/build"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RES_DIR="$APP_BUNDLE/Contents/Resources"
APP_EXEC="$APP_NAME"
SHARED_UI_DIR="$GEA_ENGINE/ui"
# Generated C++ is build output too, and a sibling of the bundles rather than
# a child: the runtime walks two directories up from a .app to find its
# namespace root and appends an app id, so a dot-prefixed sibling is invisible
# to that lookup while staying inside the one directory `rm -rf` clears.
GENERATED_DIR="$MACOS_OUTPUT_ROOT/.generated/$MACOS_OUTPUT_SUBPATH"

# Ninja avoids the per-object Bash/sed/tr dependency scan on incremental and
# no-op builds. Keep the original Shell scheduler as a portable fallback and
# as an explicit comparison backend. Resolve this before generation so a bad
# override fails without doing expensive work or touching build outputs.
MACOS_GENERATOR="${GEA_MACOS_GENERATOR:-}"
if [[ -z "$MACOS_GENERATOR" ]]; then
  if command -v ninja >/dev/null 2>&1; then
    MACOS_GENERATOR="Ninja"
  else
    MACOS_GENERATOR="Shell"
  fi
fi
case "$MACOS_GENERATOR" in
  Ninja)
    if ! command -v ninja >/dev/null 2>&1; then
      echo "GEA_MACOS_GENERATOR=Ninja requested, but ninja is not installed" >&2
      exit 1
    fi
    ;;
  Shell) ;;
  *)
    echo "GEA_MACOS_GENERATOR must be 'Ninja' or 'Shell' (got '$MACOS_GENERATOR')" >&2
    exit 1
    ;;
esac

# Generated sources, PCH files, dependency files, objects, and the final app
# bundle are all output-namespace-local shared state. Two builds of the same
# app and output tag must not update those trees concurrently; different tags
# intentionally receive disjoint generated/dist trees and locks. A generator
# can otherwise rewrite a runtime source after another invocation built its
# PCH, and clang then (correctly) rejects the now-stale PCH halfway through the
# build. `mkdir` is atomic on macOS and avoids depending on the non-system
# `flock` utility. A PID-owned
# directory also lets a later build recover a lock left by SIGKILL or a crashed
# terminal session.
mkdir -p "$DIST_DIR"
BUILD_LOCK_DIR="$DIST_DIR/.build.lock"
acquire_build_lock() {
  local owner=""
  local empty_owner_retries=0
  while true; do
    if mkdir "$BUILD_LOCK_DIR" 2>/dev/null; then
      if ! printf '%s\n' "$$" > "$BUILD_LOCK_DIR/pid"; then
        rmdir "$BUILD_LOCK_DIR" 2>/dev/null || true
        echo "Cannot record ownership for macOS build lock: $BUILD_LOCK_DIR" >&2
        return 1
      fi
      return 0
    fi
    # `mkdir` can also fail because the parent is missing/unwritable or because
    # a non-directory occupies the path. Those are configuration errors, not
    # lock contention; never turn them into an infinite retry loop.
    if [[ ! -d "$BUILD_LOCK_DIR" ]]; then
      echo "Cannot create macOS build lock: $BUILD_LOCK_DIR" >&2
      return 1
    fi
    owner="$(cat "$BUILD_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      echo "macOS build of '$MACOS_BUILD_LABEL' is already running (pid $owner)" >&2
      return 1
    fi
    # There is a very small interval between atomic mkdir and writing the pid.
    # Give a new owner time to finish publishing instead of deleting its lock.
    if [[ -z "$owner" && "$empty_owner_retries" -lt 20 ]]; then
      empty_owner_retries=$((empty_owner_retries + 1))
      sleep 0.05
      continue
    fi
    rm -rf "$BUILD_LOCK_DIR"
    empty_owner_retries=0
  done
}

release_build_lock() {
  local owner=""
  owner="$(cat "$BUILD_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$owner" == "$$" ]]; then
    rm -rf "$BUILD_LOCK_DIR"
  fi
}

cleanup_build_locks() {
  local status="$?"
  trap - EXIT HUP INT TERM
  # No writer may outlive the same-output-namespace correctness lock. Terminate
  # and reap the exact generator/Ninja/compiler trees owned by this invocation
  # first, then release locks in reverse acquisition order.
  macos_terminate_and_reap_build_children
  release_build_lock
  gea_release_heavy_build_lock
  return "$status"
}

handle_build_interrupt() {
  local status="$1"
  trap - HUP INT TERM
  exit "$status"
}

# Normal builds remain concurrent because the shared helper is opt-in. When
# benchmark serialization is requested, acquire it before the namespace-local
# correctness lock. Duplicate builds of one app+tag remain impossible either way.
gea_acquire_heavy_build_lock "$HEAVY_BUILD_LOCK_PATH" macos "$MACOS_BUILD_LABEL"
trap cleanup_build_locks EXIT
trap 'handle_build_interrupt 129' HUP
trap 'handle_build_interrupt 130' INT
trap 'handle_build_interrupt 143' TERM
acquire_build_lock

# Preserve the executable and resource outputs so a true no-op can skip linking,
# icon conversion, resource copying, and codesigning. The resource synchronizer
# below owns stale-file removal for its font/config outputs. The cache-off mode
# intentionally retains the old clean-and-restage behavior for A/B benchmarks.
if [[ "$MACOS_PIPELINE_CACHE" == "0" ]]; then rm -rf "$RES_DIR"; fi
mkdir -p "$MACOS_DIR" "$RES_DIR" "$BUILD_DIR"
BUNDLE_CONTENT_CHANGED=0

INFO_PLIST_TMP="$BUILD_DIR/Info.plist.tmp.$$"
sed -e "s/@APP_EXEC@/$APP_EXEC/g" \
    -e "s/@APP_ID@/$APP_ID/g" \
    -e "s/@APP_NAME@/$APP_NAME/g" \
    "$ROOT_DIR/targets/macos/Info.plist.in" > "$INFO_PLIST_TMP"
if replace_content_stable "$APP_BUNDLE/Contents/Info.plist" "$INFO_PLIST_TMP"; then
  BUNDLE_CONTENT_CHANGED=1
fi
timing_mark bootstrap

# Resolve package metadata once per app. Bash 3.2 has no associative arrays, so
# keep parallel indexed arrays and publish the result through a global instead
# of command substitution (which would update the cache in a subshell).
resolve_app_meta() {
  local id="$1"
  local index
  RESOLVED_APP_META=""
  for ((index = 0; index < ${#APP_META_CACHE_IDS[@]}; index++)); do
    if [[ "${APP_META_CACHE_IDS[$index]}" == "$id" ]]; then
      RESOLVED_APP_META="${APP_META_CACHE_VALUES[$index]}"
      return 0
    fi
  done
  RESOLVED_APP_META="$(node "$GEA_CLI" apps inspect "$id" --format shell 2>/dev/null || true)"
  APP_META_CACHE_IDS+=("$id")
  APP_META_CACHE_VALUES+=("$RESOLVED_APP_META")
}

# Resolve an app's source directory from package.json `gea` metadata. By the
# time later bundle/resource stages call this, generate_app has populated the
# parent-shell cache for every resident.
resolve_app_dir() {
  local id="$1"
  local root _entry _runtime _name
  resolve_app_meta "$id"
  if [[ -z "$RESOLVED_APP_META" ]]; then echo ""; return; fi
  IFS=$'\t' read -r root _entry _runtime _name < <(printf "%s\n" "$RESOLVED_APP_META")
  echo "$root"
}

# Cheap read-only equivalent of the post-generation finalizer for no-op cache
# validation. Avoiding a Node process per resident saves meaningful traversal
# time while preserving the same ownership invariants.
apple_native_cached_output_is_current() {
  local outDir="$1"
  local expectedState="$2"
  local supportPath="$outDir/generated_support.hpp"
  local metadataPath="$outDir/gea-apple-metadata.json"
  local bridgeDir="$outDir/gea/apple"
  local bridgeHeader="$bridgeDir/native_bridge.h"
  local bridgeSource="$bridgeDir/native_bridge.mm"
  local bridgeInclude='#include "gea/apple/native_bridge.h"'
  local state="0"
  case "$expectedState" in 0|1) ;; *) return 1 ;; esac
  [[ -f "$supportPath" && -s "$supportPath" ]] || return 1
  if grep -Fq "$bridgeInclude" "$supportPath"; then
    [[ -f "$bridgeHeader" && -s "$bridgeHeader" ]] || return 1
    [[ -f "$bridgeSource" && -s "$bridgeSource" ]] || return 1
    state="1"
  elif [[ -e "$metadataPath" || -L "$metadataPath" || -e "$bridgeDir" || -L "$bridgeDir" ]]; then
    return 1
  fi
  [[ "$state" == "$expectedState" ]]
}

find_generation_input_newer_than() {
  local reference="$1"
  local appDir="$2"
  shift 2
  local found=""
  local referenceEpoch=""
  local nowEpoch=""
  referenceEpoch="$(stat -f %m "$reference" 2>/dev/null || stat -c %Y "$reference" 2>/dev/null || true)"
  nowEpoch="$(date +%s)"
  # A future-dated sentinel makes every real input appear older indefinitely
  # (clock adjustment, restored build artifact, or a manual `touch -t`). Treat
  # that as stale state instead of silently compiling old generated C++.
  if [[ "$referenceEpoch" =~ ^[0-9]+$ ]] && (( referenceEpoch > nowEpoch + 5 )); then
    echo "clock-skew:$reference"
    return
  fi
  found=$(find "$appDir" \( -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.css' -o -name '*.json' \) \
            -not -path '*/node_modules/*' -not -path '*/dist/*' \
            -newer "$reference" -print -quit 2>/dev/null)
  if [[ -n "$found" ]]; then
    echo "$found"
    return
  fi

  local inputs=(
    "$GEA_CORE/scripts/build-gea-vite-geatsc.mjs"
    "$GEA_CORE/scripts/gea-bundle-type-hints.mjs"
    "$GEA_CORE/scripts/gea-embedded-compat-transform.mjs"
    "$GEA_CORE/scripts/generate-gea-embedded-assets.mjs"
    "$GEA_CORE/scripts/generate-gea-embedded-fonts.mjs"
    "$ROOT_DIR/targets/macos/check-module-graph-freshness.mjs"
    "$GEA_PLUGIN/dist"
    "$GEA_APPLE_NATIVE_PLUGIN/dist"
    "$ROOT_DIR/dist"
    "$ROOT_DIR/runtime"
    "$GEA_CORE/runtime.ts"
    "$GEA_CORE/components"
  )
  local extraInput
  for extraInput in "$@"; do
    inputs+=("$extraInput")
  done
  local input
  for input in "${inputs[@]}"; do
    [[ -e "$input" ]] || continue
    if [[ -f "$input" ]]; then
      if [[ "$input" -nt "$reference" ]]; then
        echo "$input"
        return
      fi
      continue
    fi
    found=$(find "$input" \( -name '*.tsx' -o -name '*.ts' -o -name '*.jsx' -o -name '*.js' -o -name '*.mjs' -o -name '*.css' -o -name '*.json' -o -name '*.cpp' -o -name '*.h' \) \
              -not -path '*/node_modules/*' \
              -newer "$reference" -print -quit 2>/dev/null)
    if [[ -n "$found" ]]; then
      echo "$found"
      return
    fi
  done
}

tree_fingerprint() {
  local root="$1"
  node - "$root" <<'NODE'
const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')
const root = process.argv[2]
const files = []
const walk = (dir) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(full)
    else if (entry.isFile()) files.push(full)
  }
}
walk(root)
files.sort()
const hash = crypto.createHash('sha256')
for (const file of files) {
  hash.update(path.relative(root, file))
  hash.update('\0')
  hash.update(fs.readFileSync(file))
  hash.update('\0')
}
process.stdout.write(hash.digest('hex'))
NODE
}

# Run the JSX → C++ pipeline for one app, optionally with a unique entry-
# symbol prefix (resident-app build).
generate_app() {
  local id="$1"
  local outDir="$2"
  local prefix="$3"  # empty = no prefix (single-app mode, top-level)
  local appMeta appRoot _appName
  local appDir=""
  local entry="index.tsx"
  local appRuntime=""
  resolve_app_meta "$id"
  appMeta="$RESOLVED_APP_META"
  if [[ -n "$appMeta" ]]; then
    IFS=$'\t' read -r appRoot entry appRuntime _appName < <(printf "%s\n" "$appMeta")
    appDir="$appRoot"
  fi
  if [[ -z "$appDir" || ! -f "$appDir/$entry" ]]; then
    echo "Skipping '$id' — no $entry under $appDir" >&2
    return 1
  fi
  local extraArgs=()
  if [[ -n "$prefix" ]]; then
    extraArgs=(
      --entry-symbol "${prefix}_top_level"
      --cpp-prelude-symbol "${prefix}_register_styles"
      --font-symbol-prefix "$prefix"
      --isolate-symbols
    )
  fi
  if [[ "${GEA_VITE_MODULE_GRAPH:-0}" == "1" || ( "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH:-1}" != "0" ) ]]; then
    extraArgs+=(--module-graph-out "$outDir/module-graph")
  fi
  # One generated C++ unit per source module instead of one for the whole app.
  # `read_geatsc_sources` already compiles every line of geatsc-sources.txt, so
  # this only changes how many lines there are; see the compiler's
  # docs/TRANSLATION-UNITS.md for the measured trade.
  if [[ "${GEA_PER_FILE_UNITS:-0}" == "1" ]]; then
    extraArgs+=(--per-file-units)
  fi
  if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_ONLY:-0}" == "1" ]]; then
    extraArgs+=(--module-graph-only)
  fi
  if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_COMPILE:-1}" != "0" ]]; then
    extraArgs+=(--compile-module-graph --allow-any)
  fi
  # `gea build` resolves which compiler plugins this app's packages ship and
  # names them here, so no app needs a stub file re-exporting one. The appDir
  # fallback is for a direct invocation of this script, not a decision.
  if [[ -n "${GEA_EXTRA_GEATSC_PLUGINS:-}" ]]; then
    local pluginPath
    while IFS= read -r pluginPath; do
      [[ -n "$pluginPath" ]] && extraArgs+=(--extra-geatsc-plugin "$pluginPath")
    done <<< "${GEA_EXTRA_GEATSC_PLUGINS//:/$'\n'}"
  elif [[ -f "$appDir/geatsc-plugin.mjs" ]]; then
    extraArgs+=(--extra-geatsc-plugin "$appDir/geatsc-plugin.mjs")
  fi
  if [[ "$appRuntime" == "apple-native" ]]; then
    extraArgs+=(--apple-native)
  fi
  local envSignatureFile="$outDir/.gea-build-env"
  local compilerFingerprint
  compilerFingerprint="$(node "$ROOT_DIR/targets/macos/compiler-input-fingerprint.mjs" "$GEA_COMPILER")"
  local envSignature="GEA_THREE_USE_UPSTREAM=${GEA_THREE_USE_UPSTREAM:-}
GEA_THREE_REFERENCE_DEMO=${GEA_THREE_REFERENCE_DEMO:-}
GEA_THREE_MODULE_GRAPH=${GEA_THREE_MODULE_GRAPH:-1}
GEA_VITE_MODULE_GRAPH=${GEA_VITE_MODULE_GRAPH:-0}
GEA_THREE_MODULE_GRAPH_ONLY=${GEA_THREE_MODULE_GRAPH_ONLY:-0}
GEA_THREE_MODULE_GRAPH_COMPILE=${GEA_THREE_MODULE_GRAPH_COMPILE:-1}
GEA_PER_FILE_UNITS=${GEA_PER_FILE_UNITS:-0}
GEA_CPP_TRANSLATION_UNITS=${GEA_CPP_TRANSLATION_UNITS:-}
GEA_WEBGL_AUTO_INSTANCE=${GEA_WEBGL_AUTO_INSTANCE:-}
GEA_WEBGL_AUTO_INSTANCE_TEST=${GEA_WEBGL_AUTO_INSTANCE_TEST:-}
GEA_COMPILER_FINGERPRINT=${compilerFingerprint}"
  # Only when an alternate compiler was named, so the default signature -- and
  # therefore every existing generated directory's freshness -- is unchanged.
  if [[ -n "${GEA_GEATSC_BIN:-}" ]]; then
    envSignature="$envSignature
GEA_GEATSC_FINGERPRINT=$(tree_fingerprint "$(dirname "$GEA_GEATSC_BIN")")"
  fi
  local newer=""
  local generatedNow=0
  local sourceList="$outDir/geatsc-sources.txt"
  local generationSentinel="$outDir/.gea-generation.stamp"
  local appleStateFile="$outDir/.gea-current-apple-native"
  local moduleGraphFile="$outDir/module-graph/gea-module-graph.json"
  if [[ -f "$sourceList" && -f "$generationSentinel" ]]; then
    local generationInputDirs=()
    # Every plugin that feeds generation is a generation input: an edit to one
    # must invalidate the generated C++. The paths come from the same list the
    # compiler is given, so nothing here has to guess which packages ship one.
    if [[ -n "${GEA_EXTRA_GEATSC_PLUGINS:-}" ]]; then
      local freshnessPluginPath
      while IFS= read -r freshnessPluginPath; do
        [[ -n "$freshnessPluginPath" ]] && generationInputDirs+=("$(dirname "$freshnessPluginPath")")
      done <<< "${GEA_EXTRA_GEATSC_PLUGINS//:/$'\n'}"
    fi
    newer="$(find_generation_input_newer_than "$generationSentinel" "$appDir" ${generationInputDirs[@]+"${generationInputDirs[@]}"})"
    if [[ -z "$newer" && -f "$moduleGraphFile" ]]; then
      newer="$(node "$ROOT_DIR/targets/macos/check-module-graph-freshness.mjs" \
        --graph "$moduleGraphFile" --reference "$generationSentinel")"
    fi
    if [[ ! -f "$envSignatureFile" ]] || [[ "$(cat "$envSignatureFile")" != "$envSignature" ]]; then
      newer="${newer:-env:three-scene-source}"
    fi
    if [[ ! -f "$appleStateFile" ]]; then
      newer="${newer:-env:apple-native-output-ownership}"
    else
      local cachedAppleState
      cachedAppleState="$(cat "$appleStateFile" 2>/dev/null || true)"
      if [[ "$appRuntime" == "apple-native" && "$cachedAppleState" != "1" ]]; then
        newer="${newer:-env:apple-native-runtime-state}"
      elif ! apple_native_cached_output_is_current "$outDir" "$cachedAppleState"; then
        newer="${newer:-env:apple-native-output-inconsistent}"
      fi
    fi
    if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_ONLY:-0}" == "1" && ! -f "$outDir/module-graph/gea-module-graph.json" ]]; then
      newer="${newer:-env:three-module-graph-only}"
    fi
  fi
  if [[ ! -f "$sourceList" || ! -f "$generationSentinel" || -n "$newer" ]]; then
    echo "Generating C++ for app '$id' from $appDir (entry $entry)..."
    mkdir -p "$outDir"
    if ! macos_run_tracked_child node "$GEA_CORE/scripts/build-gea-vite-geatsc.mjs" \
      --app-dir "$appDir" \
      --entry "$entry" \
      --out-dir "$outDir" \
      --geatsc-bin "${GEA_GEATSC_BIN:-$GEA_COMPILER/dist/cli.js}" \
      --geatsc-gea-plugin "$GEA_PLUGIN/dist/index.js" \
      --apple-platform macos \
      --geatsc-apple-native-plugin "$GEA_APPLE_NATIVE_PLUGIN/dist/index.js" \
      "${extraArgs[@]+"${extraArgs[@]}"}"; then
      if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_ONLY:-0}" == "1" ]]; then
        echo "Module graph generation failed for '$id'; native generation state is unchanged" >&2
        return 1
      fi
      rm -f "$generationSentinel" "$appleStateFile"
      echo "C++ generation failed for '$id'; invalidated freshness state" >&2
      return 1
    fi
    if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_ONLY:-0}" == "1" ]]; then
      echo "Generated module graph only for '$id' at $outDir/module-graph"
      exit 0
    fi
    # Derive ownership from the transformed compiler output, not the metadata
    # input consumed by the plugin. The finalizer also rejects an include whose
    # bridge files are missing, so an inconsistent generation never reaches PCH
    # or native compilation.
    local appleState
    local appleFinalizeArgs=(--out-dir "$outDir")
    if [[ "$appRuntime" == "apple-native" ]]; then
      appleFinalizeArgs+=(--expected-state 1)
    fi
    if ! appleState="$(node "$ROOT_DIR/targets/macos/finalize-apple-native-output.mjs" "${appleFinalizeArgs[@]}")"; then
      rm -f "$generationSentinel" "$appleStateFile"
      echo "C++ generation produced inconsistent Apple-native output for '$id'; invalidated freshness state" >&2
      return 1
    fi
    local envSignatureTmp="$envSignatureFile.tmp.$$"
    local appleStateTmp="$appleStateFile.tmp.$$"
    printf "%s\n" "$envSignature" > "$envSignatureTmp"
    printf "%s\n" "$appleState" > "$appleStateTmp"
    mv "$envSignatureTmp" "$envSignatureFile"
    mv "$appleStateTmp" "$appleStateFile"
    touch "$generationSentinel"
    generatedNow=1
  fi
  if [[ "$id" == "three-angle-metal" && "${GEA_THREE_MODULE_GRAPH_ONLY:-0}" == "1" ]]; then
    echo "Module graph already fresh for '$id' at $outDir/module-graph"
    exit 0
  fi
  prune_geatsc_modules "$outDir" "$generatedNow"
}

prune_geatsc_modules() {
  local outDir="$1"
  local generatedNow="${2:-0}"
  local sourceList="$outDir/geatsc-sources.txt"
  local pruneStamp="$outDir/.gea-module-prune.stamp"
  [[ "${GEA_MACOS_PRUNE_GENERATED:-1}" != "0" ]] || return 0
  [[ -f "$sourceList" && -d "$outDir/modules" ]] || return 0
  if [[ "$generatedNow" != "1" && -f "$outDir/.gea-owned-modules.json" && -f "$pruneStamp" && ! "$sourceList" -nt "$pruneStamp" ]]; then
    return 0
  fi
  local pruneArgs=(--out-dir "$outDir")
  if [[ "${GEA_MACOS_PRUNE_DRY_RUN:-0}" == "1" ]]; then
    pruneArgs+=(--dry-run)
  fi
  node "$ROOT_DIR/targets/macos/prune-generated-modules.mjs" "${pruneArgs[@]}" >/dev/null
  if [[ "${GEA_MACOS_PRUNE_DRY_RUN:-0}" != "1" ]]; then touch "$pruneStamp"; fi
}

refresh_geatsc_runtime_assets() {
  local outDir="$1"
  local runtimeDir="$GEA_COMPILER/dist/targets/cpp/runtime"
  [[ -d "$outDir" && -d "$runtimeDir" ]] || return 0
  local runtimeAsset
  # `.def` belongs in this set: geatsc's own materializer ships every
  # `.cpp`/`.h`/`.def` in the runtime dir (compiler/packages/geatsc/src/targets/
  # cpp/runtime.ts), and `runtime.cpp` `#include`s
  # `ecmascript_primitive_capabilities.def`. Omitting it only worked while the
  # emitting compiler also wrote the runtime parts; a compiler that emits just
  # its own header (geatsc) leaves the `.def` missing and the runtime PCH
  # fails with "'ecmascript_primitive_capabilities.def' file not found".
  for runtimeAsset in "$runtimeDir"/*.cpp "$runtimeDir"/*.h "$runtimeDir"/*.def; do
    [[ -f "$runtimeAsset" ]] || continue
    local dest="$outDir/$(basename "$runtimeAsset")"
    if [[ ! -f "$dest" ]] || ! cmp -s "$runtimeAsset" "$dest"; then
      cp "$runtimeAsset" "$dest"
    fi
  done
}

# Decide whether to bundle resident apps. The launcher is special: it can
# `Apps.launch('foo')` which needs an in-process app swap. For every other
# id we build standalone.
RESIDENT_IDS=()
if [[ "$APP_ID" == "app-launcher" ]]; then
  # Apps explicitly disabled for the macOS resident bundle. Currently
  # `dialer` uses WebRTC integration patterns (heavy template SFINAE) that
  # ESP-IDF's GCC accepts but Apple clang rejects — until the codegen is
  # adjusted, the dialer tile builds standalone (build-macos.sh dialer)
  # but is not embedded into app-launcher.app.
  MACOS_EXCLUDE_REGEX='^(dialer)$'
  RESIDENT_IDS=( $(node "$GEA_CLI" apps list --target geaos) )
  ORDERED_RESIDENT_IDS=(app-launcher)
  for id in "${RESIDENT_IDS[@]}"; do
    [[ "$id" == "app-launcher" ]] && continue
    ORDERED_RESIDENT_IDS+=("$id")
  done
  RESIDENT_IDS=("${ORDERED_RESIDENT_IDS[@]}")
  FILTERED=()
  for id in "${RESIDENT_IDS[@]}"; do
    if [[ "$id" =~ $MACOS_EXCLUDE_REGEX ]]; then
      echo "Excluding '$id' from app-launcher resident bundle (macOS toolchain quirks)" >&2
      continue
    fi
    FILTERED+=("$id")
  done
  RESIDENT_IDS=("${FILTERED[@]}")
fi

# Generate per-app C++ (single-app mode → directly to GENERATED_DIR;
# multi-app mode → each app under GENERATED_DIR/residents/<id>/).
GENERATED_GEATSC_SOURCES=()
GENERATED_FONT_CPP=""
GENERATED_ASSETS_CPP=""
RESIDENT_GEATSC_SOURCES=()
RESIDENT_FONT_CPPS=()
RESIDENT_ASSET_CPPS=()
RESIDENT_ENTRY_CPPS=()
RESIDENT_REGISTRY_CPP=""

read_geatsc_sources() {
  local outDir="$1"
  local sourceList="$outDir/geatsc-sources.txt"
  [[ -f "$sourceList" ]] || return
  while IFS= read -r src; do
    [[ -n "$src" && -f "$src" ]] && printf '%s\n' "$src"
  done < "$sourceList"
}

if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
  if ! generate_app "$APP_ID" "$GENERATED_DIR" ""; then
    if [[ -n "$APP_META" ]]; then
      exit 1
    fi
  fi
  refresh_geatsc_runtime_assets "$GENERATED_DIR"
  while IFS= read -r src; do GENERATED_GEATSC_SOURCES+=("$src"); done < <(read_geatsc_sources "$GENERATED_DIR")
  GENERATED_FONT_CPP="$GENERATED_DIR/gea_embedded_font_generated.cpp"
  GENERATED_ASSETS_CPP="$GENERATED_DIR/gea_embedded_assets_generated.cpp"
else
  # Track which residents successfully generated — apps without an
  # index.tsx (or otherwise skipped) shouldn't show up in the registry,
  # otherwise the launcher would reference symbols that nobody defines.
  ACTUAL_RESIDENTS=()
  for id in "${RESIDENT_IDS[@]}"; do
    safe="${id//[^A-Za-z0-9_]/_}"
    prefix="gea_resident_${safe}"
    rDir="$GENERATED_DIR/residents/$id"
    mkdir -p "$rDir"
    if ! generate_app "$id" "$rDir" "$prefix"; then continue; fi
    refresh_geatsc_runtime_assets "$rDir"
    while IFS= read -r src; do RESIDENT_GEATSC_SOURCES+=("$src"); done < <(read_geatsc_sources "$rDir")
    if [[ -f "$rDir/gea_embedded_font_generated.cpp" ]]; then
      RESIDENT_FONT_CPPS+=("$rDir/gea_embedded_font_generated.cpp")
    fi
    if [[ -f "$rDir/gea_embedded_assets_generated.cpp" ]]; then
      RESIDENT_ASSET_CPPS+=("$rDir/gea_embedded_assets_generated.cpp")
    fi
    entryCpp="$rDir/entry.cpp"
    node "$ROOT_DIR/targets/macos/generate-resident-entry.mjs" "$prefix" "$entryCpp"
    RESIDENT_ENTRY_CPPS+=("$entryCpp")
    ACTUAL_RESIDENTS+=("$id")
  done
  RESIDENT_IDS=("${ACTUAL_RESIDENTS[@]}")
  RESIDENT_REGISTRY_CPP="$GENERATED_DIR/resident_registry.cpp"
  node "$ROOT_DIR/targets/macos/generate-resident-registry.mjs" \
    "$RESIDENT_REGISTRY_CPP" "$APP_ID" "${RESIDENT_IDS[@]}"
fi
timing_mark generation

# Apple-native detection. geatsc emits gea/apple/*.mm (handle-table bridge +
# any delegate shims) when the app imports @geajs/apple/*. In that mode the
# generated geatsc app modules message-send to ::NSView / ::NSToolbar etc., so
# they must be compiled with -ObjC++, the bridge .mm files must be linked, and
# the macOS main compiles its AppKit installRootView entry (guarded by
# GEA_MACOS_HAS_APPLE_NATIVE_BRIDGE). Cocoa (which includes AppKit) is already
# on the link line.
APPLE_NATIVE=0
APPLE_BRIDGE_MMS=()
if [[ "$(cat "$GENERATED_DIR/.gea-current-apple-native" 2>/dev/null || true)" == "1" && -d "$GENERATED_DIR/gea/apple" ]]; then
  for f in "$GENERATED_DIR/gea/apple"/*.mm; do
    [[ -f "$f" ]] || continue
    APPLE_NATIVE=1
    APPLE_BRIDGE_MMS+=("$f")
  done
fi

# host/*.cpp files (image, touch, imu, …) do `#include "gea_runtime.cpp"`
# to pull in the gea_cpp_value runtime. ESP32 writes a one-line wrapper to
# the launcher's generated dir; mirror that here so the include resolves
# via the existing -I${GENERATED_DIR}.
mkdir -p "$GENERATED_DIR"
if [[ ! -f "$GENERATED_DIR/gea_runtime.cpp" ]] || [[ "$(cat "$GENERATED_DIR/gea_runtime.cpp")" != '#include "runtime_pch.h"' ]]; then
  echo '#include "runtime_pch.h"' > "$GENERATED_DIR/gea_runtime.cpp"
fi

INCLUDES=(
  -I"$ROOT_DIR/targets/macos/include"
  -I"$GENERATED_DIR"
)
# Framework include roots from the shared manifest (gea_sources.sh).
while IFS= read -r __inc; do INCLUDES+=("$__inc"); done < <(gea_fw_include_flags)
SINGLE_APP_DIR=""
if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
  SINGLE_APP_DIR="$(resolve_app_dir "$APP_ID")"
  if [[ -n "$SINGLE_APP_DIR" ]]; then
    INCLUDES+=(-I"$SINGLE_APP_DIR" -I"$SINGLE_APP_DIR/native")
  fi
fi

CXX_DEFINES=(
  -DGEA_EMBEDDED_ENABLE_VIRTUAL_KEYBOARD=0
  # Canvas ctx.fillText glyphs: rasterize at runtime from the bundle's
  # Resources/Fonts TTFs (font_registry.mm's lookupRuntimeTtfFontForFamily).
  # Windowed builds link no baked font atlas, so without this canvas text
  # fell back to the builtin bitmap font and rendered garbled. Thermalright
  # builds keep their baked atlas: the runtime path tries first, finds no
  # registered TTF bytes there, and falls through.
  -DGEA_EMBEDDED_TTF_RUNTIME_FONTS=1
)
MACOS_SHARED_RUNTIME_BUILTINS="${GEA_MACOS_SHARED_RUNTIME_BUILTINS:-0}"
case "$MACOS_SHARED_RUNTIME_BUILTINS" in
  0) ;;
  1) CXX_DEFINES+=(-DGEA_CPP_SHARED_RUNTIME_BUILTINS=1) ;;
  *) echo "GEA_MACOS_SHARED_RUNTIME_BUILTINS must be 0 or 1" >&2; exit 1 ;;
esac
GEA_MACOS_OPT_LEVEL="${GEA_MACOS_OPT_LEVEL:--O2}"
if [[ "${GEA_MACOS_FAST_DEV:-0}" == "1" && "${GEA_MACOS_OPT_LEVEL:-}" == "-O2" ]]; then
  GEA_MACOS_OPT_LEVEL="-O0"
fi
# Debug symbols do not affect runtime behavior, but full DWARF greatly increases
# compiler RSS, object size, and link I/O for generated Three.js modules. Keep
# the choice explicit and part of every compile/link signature.
GEA_MACOS_DEBUG_INFO_MODE="${GEA_MACOS_DEBUG_INFO:-none}"
case "$GEA_MACOS_DEBUG_INFO_MODE" in
  none) GEA_MACOS_DEBUG_INFO="-g0" ;;
  line-tables) GEA_MACOS_DEBUG_INFO="-gline-tables-only" ;;
  full) GEA_MACOS_DEBUG_INFO="-g" ;;
  *)
    echo "GEA_MACOS_DEBUG_INFO must be none, line-tables, or full (got '$GEA_MACOS_DEBUG_INFO_MODE')" >&2
    exit 1
    ;;
esac
THERMALRIGHT_DISPLAY_TARGET=0
THERMALRIGHT_DEFAULT_WIDTH=1280
THERMALRIGHT_DEFAULT_HEIGHT=480
THERMALRIGHT_DEFAULT_PRODUCT_ID=0x5302
case "${GEA_MACOS_DISPLAY_TARGET:-}" in
  thermalright|thermalright-hid|thermalright-usb|thermalright-1280x480|thermalright-hid-1280x480)
    THERMALRIGHT_DISPLAY_TARGET=1
    ;;
  thermalright-wide|thermalright-hid-wide|thermalright-usb-wide|thermalright-1920x462|thermalright-ly-1920x462|thermalright-1920x480|thermalright-hid-1920x480)
    THERMALRIGHT_DISPLAY_TARGET=1
    THERMALRIGHT_DEFAULT_WIDTH=1920
    THERMALRIGHT_DEFAULT_HEIGHT=462
    THERMALRIGHT_DEFAULT_PRODUCT_ID=0x5408
    ;;
esac
case "${GEA_MACOS_THERMALRIGHT_PRODUCT_ID:-}" in
  0x5408|0X5408|21512)
    THERMALRIGHT_DEFAULT_WIDTH=1920
    THERMALRIGHT_DEFAULT_HEIGHT=462
    THERMALRIGHT_DEFAULT_PRODUCT_ID="${GEA_MACOS_THERMALRIGHT_PRODUCT_ID}"
    ;;
  0x5302|0X5302|21250)
    THERMALRIGHT_DEFAULT_WIDTH=1280
    THERMALRIGHT_DEFAULT_HEIGHT=480
    THERMALRIGHT_DEFAULT_PRODUCT_ID="${GEA_MACOS_THERMALRIGHT_PRODUCT_ID}"
    ;;
esac
if [[ "$THERMALRIGHT_DISPLAY_TARGET" == "1" ]]; then
  THERMALRIGHT_WIDTH="${GEA_MACOS_THERMALRIGHT_WIDTH:-$THERMALRIGHT_DEFAULT_WIDTH}"
  THERMALRIGHT_HEIGHT="${GEA_MACOS_THERMALRIGHT_HEIGHT:-$THERMALRIGHT_DEFAULT_HEIGHT}"
  THERMALRIGHT_PRODUCT_ID="${GEA_MACOS_THERMALRIGHT_PRODUCT_ID:-$THERMALRIGHT_DEFAULT_PRODUCT_ID}"
  CXX_DEFINES+=(
    -DGEA_MACOS_THERMALRIGHT_DISPLAY_TARGET=1
    -DGEA_MACOS_THERMALRIGHT_PRODUCT_ID="$THERMALRIGHT_PRODUCT_ID"
    -DGEA_EMBEDDED_DISPLAY_WIDTH="$THERMALRIGHT_WIDTH"
    -DGEA_EMBEDDED_DISPLAY_HEIGHT="$THERMALRIGHT_HEIGHT"
    -DGEA_EMBEDDED_DISPLAY_NATIVE_WIDTH="$THERMALRIGHT_WIDTH"
    -DGEA_EMBEDDED_DISPLAY_NATIVE_HEIGHT="$THERMALRIGHT_HEIGHT"
  )
fi
if [[ "$THERMALRIGHT_DISPLAY_TARGET" == "1" && ( -f "$GENERATED_FONT_CPP" || ${#RESIDENT_FONT_CPPS[@]} -gt 0 ) ]]; then
  CXX_DEFINES+=(-DGEA_EMBEDDED_HAS_GENERATED_FONTS=1)
fi

C_SOURCES=(
  "$ROOT_DIR/targets/macos/main/macos_apps.c"
)
# Framework C sources (AnimatedGIF) from the shared manifest.
while IFS= read -r __csrc; do C_SOURCES+=("$__csrc"); done < <(gea_fw_c_sources)

CXX_SOURCES=(
  "$ROOT_DIR/targets/macos/main/macos_memory.cpp"
  "$ROOT_DIR/targets/macos/main/macos_sensors.cpp"
)
# Framework C++ sources (engine/host/elements/geaos) from the shared manifest.
# Apple (AppKit-native) lacks camera/power, uses its own run loop, and has no
# resident-app/OTA/diagnostics services — exclude those framework sources (their
# gea::platform::* / service impls are esp32/web-only) so the curated set links.
while IFS= read -r __cxxsrc; do CXX_SOURCES+=("$__cxxsrc"); done < <(gea_fw_cxx_sources | grep -vE "/(host/camera|runtime|services/[a-z_]+)\.cpp$")

GENERATED_OBJCXX_SOURCES=()
if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
  # Single-app mode: gea_app_entry.cpp provides Application::init/frame,
  # which calls the one __gea_top_level emitted by geatsc. In apple-native mode
  # that __gea_top_level builds the AppKit object graph and calls installRootView.
  CXX_SOURCES+=("$GEA_CORE/gea_app_entry.cpp")
  [[ -f "$GEA_GEAOS/resident_apps.cpp" ]] && CXX_SOURCES+=("$GEA_GEAOS/resident_apps.cpp")
  if [[ ${#GENERATED_GEATSC_SOURCES[@]} -gt 0 ]]; then
    # The vast majority of generated geatsc modules are pure C++: they reference
    # host types (NSView, NSColor, …) as plain C++ handle-wrapper structs, and the
    # ObjC-backed method bodies live in the hand-written gea/apple/*.mm bridges
    # (APPLE_BRIDGE_MMS), resolved at link. Compile those with the plain C++
    # toolchain against the cxx runtime PCH — apple-native included — instead of
    # forcing every module through `-ObjC++ -fobjc-arc`, which made each of the
    # hundreds of TUs re-parse the entire AppKit/Metal/Foundation ObjC surface
    # (native_bridge.h now guards those imports behind `#ifdef __OBJC__`).
    #
    # A small minority emit genuine ObjC syntax inline — the callback-target
    # bridge (`[[GeaAppleObjCTarget alloc] …]`, `(__bridge void *)`) that an
    # AppKit event handler lowers to. Those must stay on the .mm toolchain; detect
    # them by content and route only those to MM_SOURCES below.
    GENERATED_OBJCXX_KEYS=$'\n'
    while IFS= read -r f; do
      [[ -n "$f" ]] && GENERATED_OBJCXX_KEYS+="$f"$'\n'
    done < <(grep -lE '__bridge|GeaAppleObjCTarget|@selector|@autoreleasepool|objc_msgSend' \
      "${GENERATED_GEATSC_SOURCES[@]}" 2>/dev/null || true)
    for f in "${GENERATED_GEATSC_SOURCES[@]}"; do
      if [[ "$GENERATED_OBJCXX_KEYS" == *$'\n'"$f"$'\n'* ]]; then
        GENERATED_OBJCXX_SOURCES+=("$f")
      else
        CXX_SOURCES+=("$f")
      fi
    done
  else
    CXX_SOURCES+=("$ROOT_DIR/targets/macos/main/macos_smoke_app.cpp")
  fi
  # Embedded-asset registry (plain C++) is compiled in regardless of
  # apple-native mode — generated app modules may be Objective-C++, this never is.
  if [[ "$THERMALRIGHT_DISPLAY_TARGET" == "1" && -f "$GENERATED_FONT_CPP" ]]; then
    CXX_SOURCES+=("$GENERATED_FONT_CPP")
  fi
  [[ -f "$GENERATED_ASSETS_CPP" ]] && CXX_SOURCES+=("$GENERATED_ASSETS_CPP")
else
  # Multi-app mode: the generated registry provides Application::init/frame
  # AND ResidentApps::*, dispatching to whichever resident is active. Drop
  # gea_app_entry.cpp and the inert lib/.../resident_apps.cpp to avoid
  # duplicate symbols.
  CXX_SOURCES+=("$RESIDENT_REGISTRY_CPP")
  for f in "${RESIDENT_GEATSC_SOURCES[@]}"; do CXX_SOURCES+=("$f"); done
  for f in "${RESIDENT_FONT_CPPS[@]}"; do CXX_SOURCES+=("$f"); done
  for f in "${RESIDENT_ASSET_CPPS[@]}"; do CXX_SOURCES+=("$f"); done
  for f in "${RESIDENT_ENTRY_CPPS[@]}"; do CXX_SOURCES+=("$f"); done
fi

MM_SOURCES=(
  # gea::platform::audio — the AVAudioEngine backend, shared verbatim with iOS.
  "$ROOT_DIR/targets/shared/apple_audio.mm"
  "$ROOT_DIR/targets/macos/main/macos_main.mm"
  "$ROOT_DIR/targets/macos/main/macos_native_shell.mm"
  "$ROOT_DIR/targets/macos/main/macos_display.mm"
  "$ROOT_DIR/targets/macos/main/macos_timers.mm"
  "$ROOT_DIR/targets/macos/main/macos_renderer.mm"
  "$ROOT_DIR/targets/macos/main/color_convert.mm"
  "$ROOT_DIR/targets/macos/main/font_registry.mm"
  "$ROOT_DIR/targets/macos/main/press_bridge.mm"
  "$ROOT_DIR/targets/macos/main/image_bridge.mm"
  "$ROOT_DIR/targets/macos/main/canvas_view.mm"
  "$ROOT_DIR/targets/macos/main/thermalright_hid_display.mm"
  "$ROOT_DIR/targets/macos/main/macos_app_platform.mm"
  "$ROOT_DIR/targets/macos/main/macos_device_control.mm"
  "$ROOT_DIR/targets/macos/main/macos_host_device_control.mm"
  "$ROOT_DIR/targets/macos/main/macos_network.mm"
)

if [[ -n "$SINGLE_APP_DIR" ]]; then
  while IFS= read -r native_src; do
    [[ -n "$native_src" ]] || continue
    # nativeSourcePaths are already resolved and absolute -- an entry naming a
    # file in one of the app's packages does not live under the app root, so
    # re-joining it there would silently drop it.
    case "$native_src" in
      /*) full_src="$native_src" ;;
      *) full_src="$SINGLE_APP_DIR/$native_src" ;;
    esac
    [[ -f "$full_src" ]] || continue
    case "$full_src" in
      *.c) C_SOURCES+=("$full_src") ;;
      *.m|*.mm) MM_SOURCES+=("$full_src") ;;
      *.cc|*.cpp|*.cxx) CXX_SOURCES+=("$full_src") ;;
    esac
  done < <(node "$GEA_CLI" apps inspect "$APP_ID" --json | node -e "let data=''; process.stdin.on('data', c => data += c); process.stdin.on('end', () => { const app = JSON.parse(data); for (const src of app.nativeSourcePaths || app.nativeSources || []) console.log(src); });")
fi

# Apple-native: the hand-written AppKit handle-table bridges, plus the handful of
# generated modules that emit inline ObjC (the callback-target bridge), need the
# .mm toolchain (-ObjC++ -fobjc-arc). Everything else compiled as plain C++ above.
if [[ "$APPLE_NATIVE" == "1" ]]; then
  for f in ${APPLE_BRIDGE_MMS[@]+"${APPLE_BRIDGE_MMS[@]}"}; do MM_SOURCES+=("$f"); done
  for f in ${GENERATED_OBJCXX_SOURCES[@]+"${GENERATED_OBJCXX_SOURCES[@]}"}; do MM_SOURCES+=("$f"); done
fi

OBJ_FILES=()

CCACHE_PREFIX=()
if [[ "${GEA_MACOS_CCACHE:-1}" != "0" ]]; then
  if command -v sccache >/dev/null 2>&1; then
    CCACHE_PREFIX=(sccache)
  elif command -v ccache >/dev/null 2>&1; then
    CCACHE_PREFIX=(ccache)
  fi
fi
# macOS still ships Bash 3.2, where expanding an explicitly empty array under
# `set -u` raises "unbound variable".  Keep the cache prefix genuinely
# optional so GEA_MACOS_CCACHE=0 can exercise an authoritative cold build.
CLANG_CMD=(${CCACHE_PREFIX[@]+"${CCACHE_PREFIX[@]}"} clang)
CLANGXX_CMD=(${CCACHE_PREFIX[@]+"${CCACHE_PREFIX[@]}"} clang++)
MACOS_COMPILER_VERSION="$("${CLANGXX_CMD[@]}" --version 2>/dev/null | head -n 1 || true)"

# Mangle a source path into a unique object filename. Return through a global
# variable so the hundreds of calls made while writing build.ninja do not each
# fork a Bash command-substitution subshell.
OBJ_PATH_RESULT=""
set_obj_path() {
  local src="$1"
  local suffix="$2"
  local rel="${src#$ROOT_DIR/}"
  rel="${rel#$MACOS_OUTPUT_ROOT/}"
  rel="${rel%.cpp}"
  rel="${rel%.mm}"
  rel="${rel%.c}"
  rel="${rel//\//__}"
  OBJ_PATH_RESULT="$BUILD_DIR/${rel}${suffix}"
}

compile_signature() {
  local kind="$1"
  {
    printf 'kind=%s\n' "$kind"
    printf 'opt=%s\n' "$GEA_MACOS_OPT_LEVEL"
    printf 'debug=%s\n' "$GEA_MACOS_DEBUG_INFO"
    printf 'clang='
    printf '%s ' "${CLANG_CMD[@]}"
    printf '\nclangxx='
    printf '%s ' "${CLANGXX_CMD[@]}"
    printf '\ncompiler-version=%s\n' "$MACOS_COMPILER_VERSION"
    printf 'defines='
    printf '%s ' "${CXX_DEFINES[@]}"
    printf '\nincludes='
    printf '%s ' "${INCLUDES[@]}"
    printf '\n'
  }
}

depfile_has_newer_input() {
  local depfile="$1"
  local obj="$2"
  [[ -f "$depfile" ]] || return 0
  local dep
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    dep="${dep//\\ / }"
    if [[ -e "$dep" && "$dep" -nt "$obj" ]]; then
      return 0
    fi
  done < <(sed -e ':again' -e '/\\$/N' -e 's/\\\n/ /' -e 'tagain' -e 's/^[^:]*: //' "$depfile" | tr ' ' '\n' | sed -e 's/\\$//' -e '/^$/d')
  return 1
}

needs_compile() {
  local src="$1"
  local obj="$2"
  local sigFile="$3"
  local sig="$4"
  [[ -f "$obj" ]] || return 0
  [[ -f "$sigFile" ]] || return 0
  [[ "$(cat "$sigFile")" == "$sig" ]] || return 0
  [[ "$src" -nt "$obj" ]] && return 0
  depfile_has_newer_input "$obj.d" "$obj" && return 0
  return 1
}

# macOS ships bash 3.2, where "${arr[@]}" on an EMPTY array is an unbound-
# variable error under `set -u` — RESIDENT_GEATSC_SOURCES is only populated in
# multi-app mode, so guard with the [@]+ idiom (same as native-test-common.sh).
GEATSC_GENERATED_SOURCES=()
for f in ${GENERATED_GEATSC_SOURCES[@]+"${GENERATED_GEATSC_SOURCES[@]}"}; do GEATSC_GENERATED_SOURCES+=("$f"); done
for f in ${RESIDENT_GEATSC_SOURCES[@]+"${RESIDENT_GEATSC_SOURCES[@]}"}; do GEATSC_GENERATED_SOURCES+=("$f"); done
GEATSC_GENERATED_SOURCE_KEYS=$'\n'
for f in ${GEATSC_GENERATED_SOURCES[@]+"${GEATSC_GENERATED_SOURCES[@]}"}; do
  GEATSC_GENERATED_SOURCE_KEYS+="$f"$'\n'
done

is_geatsc_generated_source() {
  local src="$1"
  [[ "$GEATSC_GENERATED_SOURCE_KEYS" == *$'\n'"$src"$'\n'* ]]
}

timing_mark source-graph
# Precompiled headers, two levels, one pair per generated directory.
#
# Level one is the RUNTIME layer: `<stem>.runtime.hpp`, the prelude the
# compiler writes for a `--per-file-units` compile (standard headers, the
# hosts' preambles, gea_runtime.h, the hosts' headers). It is independent of
# the program's declarations, so it is built once per generated directory and
# reused across every unit and every rebuild until the runtime or the flags
# change. (`runtime_pch.h` is the previous compiler's equivalent and is honored
# only in a directory that compiler generated.)
#
# Level two is the PROGRAM layer: the shared `<stem>.hpp` the same compile
# names beside it in `geatsc-header.txt`, built ON TOP of the runtime PCH with
# `-include-pch` (clang's chained PCH). Every unit of that directory then takes
# `-include-pch <program>.pch`, which loads both layers, and its own
# `#include "<stem>.hpp"` is skipped because the PCH recorded the guard. A
# change to the program's declarations rebuilds only this small top layer; the
# runtime layer is untouched. Without it every one of the N units re-parsed the
# whole runtime -- the compiler's docs/TRANSLATION-UNITS.md measured that at
# ~1.3s per unit, most of a small unit's compile.
#
# A `single`-layout directory of this compiler names no header and takes no
# PCH: its one unit carries its own prelude, and nothing preamble-exact exists
# to precompile for it.
#
# macOS bash 3.2 has no associative arrays, so the registry is three parallel
# arrays indexed together: the generated directory, and the PCH a cxx / mm
# unit from that directory is compiled against.
PCH_DIRS=()
PCH_CXX=()
PCH_MM=()

# The two headers a per-file compile named in `geatsc-header.txt`
# (`program=<path>` and `runtime=<path>` lines), for one generated directory.
# The runtime layer MUST be the compiler's `<stem>.runtime.hpp`, never
# `generated_support.hpp`: the hosts' preambles precede `gea_runtime.h` and
# decide what it declares, and a PCH built without them declares engine
# stand-ins that collide with the engine's own types in every unit.
pch_sources_for_dir() {
  local dir="$1"
  local manifest="$dir/geatsc-header.txt"
  PCH_PROGRAM_SOURCE_RESULT=""
  PCH_RUNTIME_SOURCE_RESULT=""
  if [[ -f "$manifest" ]]; then
    local line
    while IFS= read -r line; do
      case "$line" in
        program=*) [[ -f "${line#program=}" ]] && PCH_PROGRAM_SOURCE_RESULT="${line#program=}" ;;
        runtime=*) [[ -f "${line#runtime=}" ]] && PCH_RUNTIME_SOURCE_RESULT="${line#runtime=}" ;;
      esac
    done < "$manifest"
  fi
  # The previous compiler's runtime umbrella, honored only where it generated
  # the directory and this compiler named nothing; a single-unit directory of
  # this compiler has no preamble-exact header to precompile and takes none.
  if [[ -z "$PCH_RUNTIME_SOURCE_RESULT" && -z "$PCH_PROGRAM_SOURCE_RESULT" && -f "$dir/runtime_pch.h" ]]; then
    PCH_RUNTIME_SOURCE_RESULT="$dir/runtime_pch.h"
  fi
}

# Build one PCH from one header, optionally chained on another PCH. The
# signature is the completion marker (see needs_compile): invalidate it before
# touching outputs, publish the PCH/depfile atomically, the signature last, so
# a killed clang leaves the prior PCH intact but untrusted. A chained PCH also
# rebuilds whenever the PCH under it was rebuilt, because clang validates the
# chain by identity, not by content.
build_pch() {
  local kind="$1"
  local src="$2"
  local pch="$3"
  local chained="${4:-}"
  local label="$5"
  local sigFile="$pch.sig"
  local failFile="$pch.failed"
  local sig
  local pchTmp="$pch.tmp.$$"
  local depTmp="$pch.d.tmp.$$"
  local sigTmp="$sigFile.tmp.$$"
  local chainArgs=()
  [[ -n "$chained" ]] && chainArgs=(-include-pch "$chained")
  sig="$(compile_signature "pch-$kind")"$'\n'"source=$src"$'\n'"chained=$chained"
  # Retry a prior failure. The PCH includes generated runtime and host headers
  # whose contents are not part of this direct-source signature, so an exact
  # `.failed` marker can become stale while `$src` itself stays unchanged.
  if needs_compile "$src" "$pch" "$sigFile" "$sig" || { [[ -n "$chained" && "$chained" -nt "$pch" ]]; }; then
    echo "Building $label PCH ($kind)..."
    rm -f "$sigFile" "$failFile" "$pchTmp" "$depTmp" "$sigTmp"
    # A precompiled header is an optimization and nothing else: every unit
    # compiles correctly without one. So a header that will not compile
    # degrades this directory to no PCH and says so, rather than failing a
    # build that would otherwise succeed. The case that forced this: a
    # directory the previous compiler generated leaves a `runtime_pch.h`
    # behind, this compiler does not ship the `.def` files that header
    # includes, and honoring it killed every single-layout build of an app
    # whose directory still carried one.
    local status=0
    case "$kind" in
      cxx)
        macos_run_tracked_child "${CLANGXX_CMD[@]}" -std=c++20 "$GEA_MACOS_OPT_LEVEL" "${CXX_DEFINES[@]}" "${INCLUDES[@]}" \
          ${chainArgs[@]+"${chainArgs[@]}"} \
          -x c++-header -MMD -MP -MF "$depTmp" -MT "$pch" "$src" -o "$pchTmp" || status=$?
        ;;
      mm)
        macos_run_tracked_child "${CLANGXX_CMD[@]}" -std=c++20 -ObjC++ -fobjc-arc "$GEA_MACOS_OPT_LEVEL" "${CXX_DEFINES[@]}" "${INCLUDES[@]}" \
          ${chainArgs[@]+"${chainArgs[@]}"} \
          -x objective-c++-header -MMD -MP -MF "$depTmp" -MT "$pch" "$src" -o "$pchTmp" || status=$?
        ;;
    esac
    if [[ "$status" != "0" ]]; then
      rm -f "$pchTmp" "$depTmp" "$sigTmp" "$pch" "$pch.d"
      printf "%s\n" "$sig" > "$failFile"
      echo "warning: $label PCH ($kind) failed to build from $src; continuing without it -- every unit in ${src%/*} will re-parse the runtime instead." >&2
      return 1
    fi
    printf "%s\n" "$sig" > "$sigTmp"
    mv "$pchTmp" "$pch"
    mv "$depTmp" "$pch.d"
    mv "$sigTmp" "$sigFile"
  fi
}

# Both levels for one generated directory and one kind; records the PCH its
# units take (the program layer when there is one, else the runtime layer).
build_pchs_for_dir() {
  local dir="$1"
  local kind="$2"
  local index="$3"
  [[ "${GEA_MACOS_PCH:-1}" != "0" ]] || return 0
  pch_sources_for_dir "$dir"
  local runtimeSrc="$PCH_RUNTIME_SOURCE_RESULT"
  [[ -n "$runtimeSrc" ]] || return 0
  local rel="${dir#$ROOT_DIR/}"
  rel="${rel#$MACOS_OUTPUT_ROOT/}"
  rel="${rel//\//__}"
  local runtimePch="$BUILD_DIR/${rel}.runtime_${kind}.pch"
  # No runtime layer means no chain to hang the program layer on, so the whole
  # directory compiles bare. A program layer that fails on its own still
  # leaves the runtime layer usable, which is most of the win.
  build_pch "$kind" "$runtimeSrc" "$runtimePch" "" "runtime" || return 0
  local unitPch="$runtimePch"
  if [[ -n "$PCH_PROGRAM_SOURCE_RESULT" ]]; then
    local programPch="$BUILD_DIR/${rel}.program_${kind}.pch"
    if build_pch "$kind" "$PCH_PROGRAM_SOURCE_RESULT" "$programPch" "$runtimePch" "program"; then unitPch="$programPch"; fi
  fi
  case "$kind" in
    cxx) PCH_CXX[$index]="$unitPch" ;;
    mm) PCH_MM[$index]="$unitPch" ;;
  esac
}

# The PCH a generated source is compiled against, by its directory; empty when
# none was built. `${src%/*}` is dirname without a subshell -- this runs once
# per source on both compile paths.
pch_for_source() {
  local kind="$1"
  local src="$2"
  local dir="${src%/*}"
  local i
  PCH_FOR_SOURCE_RESULT=""
  for i in ${PCH_DIRS[@]+"${!PCH_DIRS[@]}"}; do
    if [[ "${PCH_DIRS[$i]}" == "$dir" ]]; then
      case "$kind" in
        cxx) PCH_FOR_SOURCE_RESULT="${PCH_CXX[$i]}" ;;
        mm) PCH_FOR_SOURCE_RESULT="${PCH_MM[$i]}" ;;
      esac
      return 0
    fi
  done
}

# Every directory a generated source lives in, once each, in first-seen order.
for src in ${GEATSC_GENERATED_SOURCES[@]+"${GEATSC_GENERATED_SOURCES[@]}"}; do
  dir="${src%/*}"
  seen=0
  for known in ${PCH_DIRS[@]+"${PCH_DIRS[@]}"}; do
    if [[ "$known" == "$dir" ]]; then seen=1; break; fi
  done
  if [[ "$seen" == "0" ]]; then
    PCH_DIRS+=("$dir")
    PCH_CXX+=("")
    PCH_MM+=("")
  fi
done

NEEDS_CXX_PCH=0
NEEDS_MM_PCH=0
for src in "${CXX_SOURCES[@]}"; do
  if is_geatsc_generated_source "$src"; then NEEDS_CXX_PCH=1; fi
done
# Now that generated modules compile as plain C++ against the cxx PCH, the only
# generated sources still on the .mm toolchain are the rare ones that emit inline
# ObjC (the callback-target bridge). Building the ~43MB mm runtime PCH costs far
# more than it saves for a handful of TUs, so only build it when enough generated
# .mm modules would amortize it; otherwise they compile bare (each re-parses the
# runtime once — cheaper than the PCH build). The hand-written gea/apple/*.mm
# bridges do not use the runtime, so they never need it.
MM_GENERATED_COUNT=0
for src in "${MM_SOURCES[@]}"; do
  if is_geatsc_generated_source "$src"; then MM_GENERATED_COUNT=$((MM_GENERATED_COUNT + 1)); fi
done
if [[ "$MM_GENERATED_COUNT" -ge "${GEA_MACOS_MM_PCH_THRESHOLD:-8}" ]]; then NEEDS_MM_PCH=1; fi
# Generation can take minutes. Re-establish the object-directory invariant at
# the compilation boundary so an out-of-band cleanup cannot leave the PCH and
# object writers targeting a vanished parent directory.
mkdir -p "$BUILD_DIR"
if [[ "$MACOS_SHARED_RUNTIME_BUILTINS" == "1" ]]; then
  sharedRuntimePrelude=""
  for dir in ${PCH_DIRS[@]+"${PCH_DIRS[@]}"}; do
    pch_sources_for_dir "$dir"
    if [[ -n "$PCH_RUNTIME_SOURCE_RESULT" ]]; then
      sharedRuntimePrelude="$PCH_RUNTIME_SOURCE_RESULT"
      break
    fi
  done
  if [[ -z "$sharedRuntimePrelude" ]]; then
    echo "Shared runtime builtins require a generated runtime prelude (per-file or balanced layout)" >&2
    exit 1
  fi
  # Every consumer gets the same declaration-mode flag; exactly one owner is
  # linked for the entire native build, including builds with resident apps.
  # Use the real host prelude before the runtime implementation, just as the
  # generated units do, so engine/host types retain their existing ABI.
  sharedRuntimeOwner="$BUILD_DIR/gea_runtime_builtins_owner.cpp"
  sharedRuntimeOwnerTmp="$sharedRuntimeOwner.tmp.$$"
  printf '#include "%s"\n#include "%s"\n' "$sharedRuntimePrelude" \
    "$GEA_COMPILER/src/targets/cpp/runtime/gea_runtime_builtins.cpp" > "$sharedRuntimeOwnerTmp"
  replace_content_stable "$sharedRuntimeOwner" "$sharedRuntimeOwnerTmp" || true
  CXX_SOURCES+=("$sharedRuntimeOwner")
fi
for i in ${PCH_DIRS[@]+"${!PCH_DIRS[@]}"}; do
  if [[ "$NEEDS_CXX_PCH" == "1" ]]; then build_pchs_for_dir "${PCH_DIRS[$i]}" cxx "$i"; fi
  if [[ "$NEEDS_MM_PCH" == "1" ]]; then build_pchs_for_dir "${PCH_DIRS[$i]}" mm "$i"; fi
done
timing_mark pch

compile_c() {
  local src="$1"
  local obj
  set_obj_path "$src" .o
  obj="$OBJ_PATH_RESULT"
  "${CLANG_CMD[@]}" "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} -DGEA_EMBEDDED_GIF_C_API "${INCLUDES[@]}" -c "$src" -o "$obj"
  OBJ_FILES+=("$obj")
}

compile_cxx() {
  local src="$1"
  local obj
  set_obj_path "$src" .cxx.o
  obj="$OBJ_PATH_RESULT"
  "${CLANGXX_CMD[@]}" -std=c++20 "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} "${CXX_DEFINES[@]}" "${INCLUDES[@]}" -x c++ -c "$src" -o "$obj"
  OBJ_FILES+=("$obj")
}

compile_mm() {
  local src="$1"
  local obj
  set_obj_path "$src" .mm.o
  obj="$OBJ_PATH_RESULT"
  "${CLANGXX_CMD[@]}" -std=c++20 -ObjC++ -fobjc-arc "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} "${CXX_DEFINES[@]}" "${INCLUDES[@]}" -c "$src" -o "$obj"
  OBJ_FILES+=("$obj")
}

# Parallel compile. A generated -g0 module currently peaks around 2.4 GiB in
# clang. Use eight workers on >=64 GiB machines, four on smaller hosts, and
# always cap the result by available logical CPUs. Explicit overrides win.
default_macos_jobs() {
  local logical memory pages page_size jobs
  logical="$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  memory="$(sysctl -n hw.memsize 2>/dev/null || true)"
  if ! [[ "$memory" =~ ^[0-9]+$ ]]; then
    pages="$(getconf _PHYS_PAGES 2>/dev/null || echo 0)"
    page_size="$(getconf PAGE_SIZE 2>/dev/null || echo 0)"
    if [[ "$pages" =~ ^[0-9]+$ && "$page_size" =~ ^[0-9]+$ ]]; then
      memory=$((pages * page_size))
    else
      memory=0
    fi
  fi
  jobs=4
  if (( memory >= 68719476736 )); then jobs=8; fi
  # Large generated applications have enough independent translation units to
  # keep more of an M-series Max busy.  Reserve four logical CPUs for the host
  # while using the extra RAM to avoid the swap/RSS cliff seen on smaller Macs.
  if (( memory >= 103079215104 )); then jobs=12; fi
  if [[ "$logical" =~ ^[0-9]+$ ]] && (( logical > 0 && jobs > logical )); then jobs="$logical"; fi
  printf '%s\n' "$jobs"
}

JOBS="${GEA_MACOS_JOBS:-${MAKEFLAGS_J:-$(default_macos_jobs)}}"
if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || (( JOBS < 1 )); then
  JOBS=1
fi
if [[ "$MACOS_TIMINGS" == "1" ]]; then
  printf '[macos timing] configuration generator=%s jobs=%s debug=%s opt=%s cache=%s\n' \
    "$MACOS_GENERATOR" "$JOBS" "$GEA_MACOS_DEBUG_INFO_MODE" "$GEA_MACOS_OPT_LEVEL" "$MACOS_PIPELINE_CACHE" >&2
fi

write_content_stable_file() {
  local destination="$1"
  local temporary="$2"
  if [[ -f "$destination" ]] && cmp -s "$temporary" "$destination"; then
    rm -f "$temporary"
    return
  fi
  mv "$temporary" "$destination"
}

NINJA_ESCAPED_PATH=""
set_ninja_escaped_path() {
  local value="$1"
  case "$value" in
    *$'\n'*) echo "Ninja paths may not contain newlines: $value" >&2; exit 1 ;;
  esac
  value="${value//\$/\$\$}"
  value="${value// /\$ }"
  value="${value//:/\$:}"
  NINJA_ESCAPED_PATH="$value"
}

NINJA_SHELL_QUOTED=""
set_ninja_shell_quoted() {
  local value="$1"
  case "$value" in
    *"'"*|*$'\n'*) echo "Unsupported quote/newline in Ninja command argument: $value" >&2; exit 1 ;;
  esac
  value="${value//\$/\$\$}"
  NINJA_SHELL_QUOTED="'$value'"
}

write_clang_response_file() {
  local destination="$1"
  shift
  local temporary="$destination.tmp.$$"
  : > "$temporary"
  local argument escaped
  for argument in "$@"; do
    [[ -n "$argument" ]] || continue
    escaped="${argument//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '"%s"\n' "$escaped" >> "$temporary"
  done
  write_content_stable_file "$destination" "$temporary"
}

write_ninja_signature_file() {
  local destination="$1"
  local signature="$2"
  local temporary="$destination.tmp.$$"
  printf '%s\n' "$signature" > "$temporary"
  write_content_stable_file "$destination" "$temporary"
}

write_ninja_compile_edge() {
  local output_file="$1"
  local rule="$2"
  local source_file="$3"
  local response_file="$4"
  local signature_file="$5"
  local pch_file="${6:-}"
  local escaped_output escaped_source escaped_response escaped_signature escaped_pch
  set_ninja_escaped_path "$output_file"; escaped_output="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$source_file"; escaped_source="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$response_file"; escaped_response="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$signature_file"; escaped_signature="$NINJA_ESCAPED_PATH"
  printf 'build %s: %s %s | %s %s' \
    "$escaped_output" \
    "$rule" \
    "$escaped_source" \
    "$escaped_response" \
    "$escaped_signature"
  if [[ -n "$pch_file" ]]; then
    set_ninja_escaped_path "$pch_file"; escaped_pch="$NINJA_ESCAPED_PATH"
    printf ' %s' "$escaped_pch"
  fi
  printf '\n'
}

compile_with_ninja() {
  local ninja_file="$BUILD_DIR/build.ninja"
  local ninja_tmp="$ninja_file.tmp.$$"
  local ninja_inputs_file="$BUILD_DIR/build.ninja.inputs"
  local ninja_inputs_tmp="$ninja_inputs_file.tmp.$$"
  local c_rsp="$BUILD_DIR/ninja-c.rsp"
  local cxx_rsp="$BUILD_DIR/ninja-cxx.rsp"
  local mm_rsp="$BUILD_DIR/ninja-mm.rsp"
  local c_signature_file="$BUILD_DIR/ninja-c.signature"
  local cxx_signature_file="$BUILD_DIR/ninja-cxx.signature"
  local mm_signature_file="$BUILD_DIR/ninja-mm.signature"
  local src obj

  # Ninja cannot safely import Shell-era depfiles into its binary dependency
  # database without running each edge. Rebuild that legacy tree once instead
  # of silently trusting objects whose flags/dependencies may differ. Every
  # subsequent build uses the compact .ninja_deps database.
  if [[ ! -f "$BUILD_DIR/.ninja_deps" ]] && \
     find "$BUILD_DIR" -name '*.o' -type f -print -quit 2>/dev/null | grep -q .; then
    echo "Migrating existing objects to Ninja dependency tracking (one-time rebuild)..." >&2
  fi

  # Object order is also link order. Populate it even on a graph-cache hit,
  # using in-process path mangling rather than one subshell per source.
  for src in "${C_SOURCES[@]}"; do
    set_obj_path "$src" .o; OBJ_FILES+=("$OBJ_PATH_RESULT")
  done
  for src in "${CXX_SOURCES[@]}"; do
    set_obj_path "$src" .cxx.o; OBJ_FILES+=("$OBJ_PATH_RESULT")
  done
  for src in "${MM_SOURCES[@]}"; do
    set_obj_path "$src" .mm.o; OBJ_FILES+=("$OBJ_PATH_RESULT")
  done

  # Source sizes are part of the graph: they determine the compile-edge order.
  # Compute the schedule once, then include its size/order fingerprint in the
  # graph-cache key so a regenerated module cannot leave a stale LPT schedule.
  # One Node process stats the whole source set; the no-op path still avoids the
  # much more expensive Bash graph-emission work below.
  local compile_schedule
  compile_schedule="$({
    for src in "${C_SOURCES[@]}"; do printf 'c\t%s\n' "$src"; done
    for src in "${CXX_SOURCES[@]}"; do printf 'cxx\t%s\n' "$src"; done
    for src in "${MM_SOURCES[@]}"; do printf 'mm\t%s\n' "$src"; done
  } | node "$ROOT_DIR/targets/macos/order-compile-edges.mjs")"

  # build.ninja is a pure function of these inputs. Re-emitting its hundreds of
  # edges used to cost several seconds of Bash process churn even when Ninja
  # itself needed only milliseconds to prove the graph clean.
  {
    printf 'format=5\nuse-ninja-deps=1\n'
    printf 'clang='; printf '%s\037' "${CLANG_CMD[@]}"; printf '\n'
    printf 'clangxx='; printf '%s\037' "${CLANGXX_CMD[@]}"; printf '\n'
    printf 'c-signature=%s\n' "$COMPILE_SIGNATURE_C"
    printf 'cxx-signature=%s\n' "$COMPILE_SIGNATURE_CXX"
    printf 'mm-signature=%s\n' "$COMPILE_SIGNATURE_MM"
    for i in ${PCH_DIRS[@]+"${!PCH_DIRS[@]}"}; do
      printf 'pch=%s\t%s\t%s\n' "${PCH_DIRS[$i]}" "${PCH_CXX[$i]}" "${PCH_MM[$i]}"
    done
    for src in "${C_SOURCES[@]}"; do printf 'c=%s\n' "$src"; done
    for src in "${CXX_SOURCES[@]}"; do
      if is_geatsc_generated_source "$src"; then printf 'cxx-generated=%s\n' "$src"
      else printf 'cxx=%s\n' "$src"; fi
    done
    for src in "${MM_SOURCES[@]}"; do
      if is_geatsc_generated_source "$src"; then printf 'mm-generated=%s\n' "$src"
      else printf 'mm=%s\n' "$src"; fi
    done
    local scheduled_kind scheduled_size scheduled_source
    while IFS=$'\t' read -r scheduled_kind scheduled_size scheduled_source; do
      printf 'schedule=%s\t%s\t%s\n' "$scheduled_kind" "$scheduled_size" "$scheduled_source"
    done <<< "$compile_schedule"
  } > "$ninja_inputs_tmp"

  if [[ "$MACOS_PIPELINE_CACHE" == "1" && -f "$ninja_file" && -f "$ninja_inputs_file" && \
        -f "$c_rsp" && -f "$cxx_rsp" && -f "$mm_rsp" && \
        -f "$c_signature_file" && -f "$cxx_signature_file" && -f "$mm_signature_file" ]] && \
      cmp -s "$ninja_inputs_tmp" "$ninja_inputs_file"; then
    rm -f "$ninja_inputs_tmp"
    if [[ "${GEA_MACOS_NINJA_DRY_RUN:-0}" == "1" ]]; then
      macos_run_tracked_child ninja -C "$BUILD_DIR" -f "$ninja_file" -d keepdepfile -n -j "$JOBS" gea_objects
    else
      macos_run_tracked_child ninja -C "$BUILD_DIR" -f "$ninja_file" -d keepdepfile -j "$JOBS" gea_objects
    fi
    return
  fi

  write_clang_response_file "$c_rsp" \
    "$GEA_MACOS_OPT_LEVEL" "$GEA_MACOS_DEBUG_INFO" \
    -DGEA_EMBEDDED_GIF_C_API "${INCLUDES[@]}"
  write_clang_response_file "$cxx_rsp" \
    -std=c++20 "$GEA_MACOS_OPT_LEVEL" "$GEA_MACOS_DEBUG_INFO" \
    "${CXX_DEFINES[@]}" "${INCLUDES[@]}" -x c++
  write_clang_response_file "$mm_rsp" \
    -std=c++20 -ObjC++ -fobjc-arc "$GEA_MACOS_OPT_LEVEL" "$GEA_MACOS_DEBUG_INFO" \
    "${CXX_DEFINES[@]}" "${INCLUDES[@]}"
  write_ninja_signature_file "$c_signature_file" "$COMPILE_SIGNATURE_C"
  write_ninja_signature_file "$cxx_signature_file" "$COMPILE_SIGNATURE_CXX"
  write_ninja_signature_file "$mm_signature_file" "$COMPILE_SIGNATURE_MM"

  local clang_command=""
  local clangxx_command=""
  local command_part
  for command_part in "${CLANG_CMD[@]}"; do
    set_ninja_shell_quoted "$command_part"
    clang_command+="$NINJA_SHELL_QUOTED "
  done
  for command_part in "${CLANGXX_CMD[@]}"; do
    set_ninja_shell_quoted "$command_part"
    clangxx_command+="$NINJA_SHELL_QUOTED "
  done

  local escaped_c_rsp escaped_cxx_rsp escaped_mm_rsp
  local escaped_c_signature escaped_cxx_signature escaped_mm_signature
  set_ninja_escaped_path "$c_rsp"; escaped_c_rsp="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$cxx_rsp"; escaped_cxx_rsp="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$mm_rsp"; escaped_mm_rsp="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$c_signature_file"; escaped_c_signature="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$cxx_signature_file"; escaped_cxx_signature="$NINJA_ESCAPED_PATH"
  set_ninja_escaped_path "$mm_signature_file"; escaped_mm_signature="$NINJA_ESCAPED_PATH"

  {
    printf 'ninja_required_version = 1.10\n\n'
    printf 'rule compile_c\n'
    printf '  command = rm -f ${out}.sig ${out}.tmp ${out}.d.tmp && %s"@$rsp" -MMD -MP -MF ${out}.d.tmp -MT $out -c $in -o ${out}.tmp && mv ${out}.tmp $out && mv ${out}.d.tmp ${out}.d && cp "$signature" ${out}.sig\n' "$clang_command"
    printf '  description = CC $in\n'
    printf '  depfile = ${out}.d\n'
    printf '  deps = gcc\n'
    printf '\n'
    printf 'rule compile_cxx\n'
    printf '  command = rm -f ${out}.sig ${out}.tmp ${out}.d.tmp && %s"@$rsp" $extra -MMD -MP -MF ${out}.d.tmp -MT $out -c $in -o ${out}.tmp && mv ${out}.tmp $out && mv ${out}.d.tmp ${out}.d && cp "$signature" ${out}.sig\n' "$clangxx_command"
    printf '  description = CXX $in\n'
    printf '  depfile = ${out}.d\n'
    printf '  deps = gcc\n'
    printf '\n'
    printf 'rule compile_mm\n'
    printf '  command = rm -f ${out}.sig ${out}.tmp ${out}.d.tmp && %s"@$rsp" $extra -MMD -MP -MF ${out}.d.tmp -MT $out -c $in -o ${out}.tmp && mv ${out}.tmp $out && mv ${out}.d.tmp ${out}.d && cp "$signature" ${out}.sig\n' "$clangxx_command"
    printf '  description = OBJCXX $in\n'
    printf '  depfile = ${out}.d\n'
    printf '  deps = gcc\n'
    printf '\n'

    # Ninja gives equally deep ready edges ascending build-statement IDs. Emit
    # only compile edges in the deterministic LPT-like order computed above.
    # OBJ_FILES remains in its original order, preserving link order/signatures.
    local source_kind source_size src obj extra pch quoted_pch escaped_object
    while IFS=$'\t' read -r source_kind source_size src; do
      case "$source_kind" in
        c)
          set_obj_path "$src" .o; obj="$OBJ_PATH_RESULT"
          write_ninja_compile_edge "$obj" compile_c "$src" "$c_rsp" "$c_signature_file"
          printf '  rsp = %s\n' "$escaped_c_rsp"
          printf '  signature = %s\n' "$escaped_c_signature"
          ;;
        cxx)
          set_obj_path "$src" .cxx.o; obj="$OBJ_PATH_RESULT"
          extra=""
          pch=""
          if is_geatsc_generated_source "$src"; then
            extra="-Wno-parentheses-equality"
            pch_for_source cxx "$src"
            if [[ -n "$PCH_FOR_SOURCE_RESULT" ]]; then
              pch="$PCH_FOR_SOURCE_RESULT"
              set_ninja_shell_quoted "$pch"; quoted_pch="$NINJA_SHELL_QUOTED"
              extra+=" -include-pch $quoted_pch"
            fi
          fi
          write_ninja_compile_edge "$obj" compile_cxx "$src" "$cxx_rsp" "$cxx_signature_file" "$pch"
          printf '  rsp = %s\n' "$escaped_cxx_rsp"
          printf '  signature = %s\n' "$escaped_cxx_signature"
          printf '  extra = %s\n' "$extra"
          ;;
        mm)
          set_obj_path "$src" .mm.o; obj="$OBJ_PATH_RESULT"
          extra=""
          pch=""
          if is_geatsc_generated_source "$src"; then
            extra="-Wno-parentheses-equality"
            pch_for_source mm "$src"
            if [[ -n "$PCH_FOR_SOURCE_RESULT" ]]; then
              pch="$PCH_FOR_SOURCE_RESULT"
              set_ninja_shell_quoted "$pch"; quoted_pch="$NINJA_SHELL_QUOTED"
              extra+=" -include-pch $quoted_pch"
            fi
          fi
          write_ninja_compile_edge "$obj" compile_mm "$src" "$mm_rsp" "$mm_signature_file" "$pch"
          printf '  rsp = %s\n' "$escaped_mm_rsp"
          printf '  signature = %s\n' "$escaped_mm_signature"
          printf '  extra = %s\n' "$extra"
          ;;
        *)
          echo "Unsupported scheduled source kind: $source_kind" >&2
          return 1
          ;;
      esac
    done <<< "$compile_schedule"

    printf '\nbuild gea_objects: phony'
    local object_file
    for object_file in "${OBJ_FILES[@]}"; do
      set_ninja_escaped_path "$object_file"; escaped_object="$NINJA_ESCAPED_PATH"
      printf ' %s' "$escaped_object"
    done
    printf '\ndefault gea_objects\n'
  } > "$ninja_tmp"
  write_content_stable_file "$ninja_file" "$ninja_tmp"
  write_content_stable_file "$ninja_inputs_file" "$ninja_inputs_tmp"

  # deps=gcc normally lets Ninja remove .d files after importing them into its
  # database. Keep them so GEA_MACOS_GENERATOR=Shell can reuse Ninja objects.
  if [[ "${GEA_MACOS_NINJA_DRY_RUN:-0}" == "1" ]]; then
    macos_run_tracked_child ninja -C "$BUILD_DIR" -f "$ninja_file" -d keepdepfile -n -j "$JOBS" gea_objects
  else
    macos_run_tracked_child ninja -C "$BUILD_DIR" -f "$ninja_file" -d keepdepfile -j "$JOBS" gea_objects
  fi
}

COMPILE_FAILED=0
NINJA_DEPS_INVALIDATED=0

wait_for_compile_slot() {
  (( ${#PIDS[@]} < JOBS )) && return 0
  # macOS ships bash 3.2, which has neither `wait -n` (wait for ANY job) nor
  # its `-p` pid capture. Wait on the OLDEST outstanding job instead — a
  # slightly more conservative slot policy that still honours the JOBS cap and
  # keeps the pipeline saturated in practice.
  local finished_pid="${PIDS[0]}"
  if ! wait "$finished_pid"; then
    COMPILE_FAILED=1
    # Do not keep feeding the queue after the first failed TU. Let only the
    # already-running peers finish (at most JOBS-1), then return failure; with
    # `set -e` the caller exits and releases the per-app build lock.
    local peer_pid
    for peer_pid in ${PIDS[@]+"${PIDS[@]}"}; do
      [[ "$peer_pid" == "$finished_pid" ]] && continue
      wait "$peer_pid" 2>/dev/null || true
    done
    PIDS=()
    return 1
  fi
  local next=()
  local pid
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    [[ "$pid" == "$finished_pid" ]] && continue
    next+=("$pid")
  done
  PIDS=(${next[@]+"${next[@]}"})
}

wait_for_all_compiles() {
  local pid
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    if ! wait "$pid"; then
      COMPILE_FAILED=1
    fi
  done
  PIDS=()
  if (( COMPILE_FAILED != 0 )); then
    exit 1
  fi
}

queue_compile() {
  local kind="$1"
  local src="$2"
  local obj
  local sig
  local sigFile
  local objTmp
  local depTmp
  local sigTmp
  local pchArgs=()
  local generatedWarningArgs=()
  case "$kind" in
    c)   set_obj_path "$src" .o; obj="$OBJ_PATH_RESULT" ;;
    cxx) set_obj_path "$src" .cxx.o; obj="$OBJ_PATH_RESULT" ;;
    mm)  set_obj_path "$src" .mm.o; obj="$OBJ_PATH_RESULT" ;;
  esac
  OBJ_FILES+=("$obj")
  case "$kind" in
    c)   sig="$COMPILE_SIGNATURE_C" ;;
    cxx) sig="$COMPILE_SIGNATURE_CXX" ;;
    mm)  sig="$COMPILE_SIGNATURE_MM" ;;
  esac
  sigFile="$obj.sig"
  if is_geatsc_generated_source "$src"; then
    # Abbreviated generated method templates frequently compare dependent
    # values inside an extra pair of parentheses. Clang's default diagnostic
    # produces several notes per instantiation (thousands for Three.js apps),
    # adding log I/O and diagnostic work without identifying a source bug.
    generatedWarningArgs=(-Wno-parentheses-equality)
    case "$kind" in
      cxx|mm)
        pch_for_source "$kind" "$src"
        [[ -n "$PCH_FOR_SOURCE_RESULT" ]] && pchArgs=(-include-pch "$PCH_FOR_SOURCE_RESULT")
        ;;
    esac
  fi
  if ! needs_compile "$src" "$obj" "$sigFile" "$sig"; then
    return
  fi
  objTmp="$obj.tmp.$$"
  depTmp="$obj.d.tmp.$$"
  sigTmp="$sigFile.tmp.$$"
  # Keep the last successful object available until clang succeeds, but remove
  # its completion marker now so interruption can never make it look current.
  rm -f "$sigFile" "$objTmp" "$depTmp" "$sigTmp"
  # If the Shell fallback recompiles anything after a fresh Ninja build, its
  # new depfile may contain a different header set than Ninja's binary deps
  # database. Drop the database so the next Ninja invocation performs the safe
  # one-time rebuild above instead of trusting stale binary dependency edges.
  if [[ "$NINJA_DEPS_INVALIDATED" == "0" ]]; then
    rm -f "$BUILD_DIR/.ninja_deps"
    NINJA_DEPS_INVALIDATED=1
  fi
  case "$kind" in
    c)
      ( "${CLANG_CMD[@]}" "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} -DGEA_EMBEDDED_GIF_C_API "${INCLUDES[@]}" \
          -MMD -MP -MF "$depTmp" -MT "$obj" -c "$src" -o "$objTmp" && \
          printf "%s\n" "$sig" > "$sigTmp" && mv "$objTmp" "$obj" && mv "$depTmp" "$obj.d" && mv "$sigTmp" "$sigFile" ) &
      ;;
    cxx)
      ( "${CLANGXX_CMD[@]}" -std=c++20 "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} "${CXX_DEFINES[@]}" "${INCLUDES[@]}" \
          ${pchArgs[@]+"${pchArgs[@]}"} ${generatedWarningArgs[@]+"${generatedWarningArgs[@]}"} \
          -x c++ -MMD -MP -MF "$depTmp" -MT "$obj" -c "$src" -o "$objTmp" && \
          printf "%s\n" "$sig" > "$sigTmp" && mv "$objTmp" "$obj" && mv "$depTmp" "$obj.d" && mv "$sigTmp" "$sigFile" ) &
      ;;
    mm)
      ( "${CLANGXX_CMD[@]}" -std=c++20 -ObjC++ -fobjc-arc "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} "${CXX_DEFINES[@]}" "${INCLUDES[@]}" \
          ${pchArgs[@]+"${pchArgs[@]}"} ${generatedWarningArgs[@]+"${generatedWarningArgs[@]}"} \
          -MMD -MP -MF "$depTmp" -MT "$obj" -c "$src" -o "$objTmp" && \
          printf "%s\n" "$sig" > "$sigTmp" && mv "$objTmp" "$obj" && mv "$depTmp" "$obj.d" && mv "$sigTmp" "$sigFile" ) &
      ;;
  esac
  PIDS+=($!)
  wait_for_compile_slot
}

COMPILE_SIGNATURE_C="$(compile_signature c)"
COMPILE_SIGNATURE_CXX="$(compile_signature cxx)"
COMPILE_SIGNATURE_MM="$(compile_signature mm)"

if [[ "$MACOS_GENERATOR" == "Ninja" ]]; then
  compile_with_ninja
else
  for src in "${C_SOURCES[@]}";   do queue_compile c   "$src"; done
  for src in "${CXX_SOURCES[@]}"; do queue_compile cxx "$src"; done
  for src in "${MM_SOURCES[@]}";  do queue_compile mm  "$src"; done
  wait_for_all_compiles
fi
timing_mark compile

# AVFoundation is unconditional: targets/shared/apple_audio.mm (the real audio
# backend, oscillators + file/PCM playback) is built into every macOS app, not
# just apple-native ones.
LINK_FRAMEWORKS=(-framework Cocoa -framework QuartzCore -framework CoreText -framework IOKit -framework ImageIO -framework CoreGraphics -framework SystemConfiguration -framework AVFoundation)
if [[ "$APPLE_NATIVE" == "1" ]]; then
  # The apple-native bridge emits Objective-C++ for every framework in the
  # metadata (UIKit + the iOS-only AVFoundation camera shims are compiled out
  # on macOS). The remaining macOS-available frameworks it references must be
  # linked. AppKit/Foundation/CoreGraphics come via Cocoa.
  LINK_FRAMEWORKS+=(
    -framework Metal -framework MetalKit -framework MapKit
    -framework CoreLocation -framework AVFoundation -framework CoreMedia
    -framework Photos
  )
fi

LINK_OUTPUT="$MACOS_DIR/$APP_EXEC"
LINK_OUTPUT_TMP="$LINK_OUTPUT.tmp.$$"
LINK_SIGNATURE_FILE="$BUILD_DIR/link.sig"
LINK_SIGNATURE_TMP="$LINK_SIGNATURE_FILE.tmp.$$"
{
  printf 'compiler=%s\n' "$MACOS_COMPILER_VERSION"
  printf 'opt=%s\n' "$GEA_MACOS_OPT_LEVEL"
  printf 'debug=%s\n' "${GEA_MACOS_DEBUG_INFO:-}"
  printf 'framework=%s\n' "${LINK_FRAMEWORKS[@]}"
  printf 'object=%s\n' "${OBJ_FILES[@]}"
} > "$LINK_SIGNATURE_TMP"

LINK_NEEDED=0
if [[ ! -x "$LINK_OUTPUT" ]] || ! cmp -s "$LINK_SIGNATURE_TMP" "$LINK_SIGNATURE_FILE"; then
  LINK_NEEDED=1
else
  for obj in "${OBJ_FILES[@]}"; do
    if [[ "$obj" -nt "$LINK_OUTPUT" ]]; then
      LINK_NEEDED=1
      break
    fi
  done
fi

if (( LINK_NEEDED != 0 )); then
  # Preserve the last complete executable until the linker succeeds. Clear both
  # completion markers first so a killed link is retried and re-signed.
  rm -f "$LINK_SIGNATURE_FILE" "$BUILD_DIR/codesign.complete" "$LINK_OUTPUT_TMP"
  macos_run_tracked_child clang++ -std=c++20 -ObjC++ -fobjc-arc "$GEA_MACOS_OPT_LEVEL" ${GEA_MACOS_DEBUG_INFO} \
    "${LINK_FRAMEWORKS[@]}" \
    "${OBJ_FILES[@]}" \
    -o "$LINK_OUTPUT_TMP"
  mv "$LINK_OUTPUT_TMP" "$LINK_OUTPUT"
  mv "$LINK_SIGNATURE_TMP" "$LINK_SIGNATURE_FILE"
else
  rm -f "$LINK_SIGNATURE_TMP"
fi
if (( LINK_NEEDED != 0 )); then BUNDLE_CONTENT_CHANGED=1; fi
timing_mark link

# Convert the app icon only when its resolved source, manifest metadata, or the
# icon tooling changed. Ten `sips` subprocesses made this the largest historical
# no-op phase.
if [[ -n "$APP_META" ]]; then
  ICON_OUTPUT="$RES_DIR/AppIcon.icns"
  ICON_INPUT_SIGNATURE_FILE="$BUILD_DIR/AppIcon.inputs"
  ICON_INPUT_SIGNATURE="$(node "$GEA_CLI" apps apple-icons "$APP_ID" --platform macos --signature)"
  ICON_NEEDED=0
  if [[ "$MACOS_PIPELINE_CACHE" == "0" || ! -f "$ICON_OUTPUT" || ! -f "$ICON_INPUT_SIGNATURE_FILE" || \
        "$(cat "$ICON_INPUT_SIGNATURE_FILE" 2>/dev/null || true)" != "$ICON_INPUT_SIGNATURE" ]]; then
    ICON_NEEDED=1
  fi
  if (( ICON_NEEDED != 0 )); then
    ICON_HASH_BEFORE="$(shasum -a 256 "$ICON_OUTPUT" 2>/dev/null | awk '{print $1}' || true)"
    node "$GEA_CLI" apps apple-icons "$APP_ID" --platform macos \
      --build-dir "$BUILD_DIR" --resources-dir "$RES_DIR" >/dev/null
    ICON_HASH_AFTER="$(shasum -a 256 "$ICON_OUTPUT" | awk '{print $1}')"
    ICON_SIGNATURE_TMP="$ICON_INPUT_SIGNATURE_FILE.tmp.$$"
    printf '%s\n' "$ICON_INPUT_SIGNATURE" > "$ICON_SIGNATURE_TMP"
    replace_content_stable "$ICON_INPUT_SIGNATURE_FILE" "$ICON_SIGNATURE_TMP" || true
    if [[ "$ICON_HASH_BEFORE" != "$ICON_HASH_AFTER" ]]; then BUNDLE_CONTENT_CHANGED=1; fi
  fi
fi

# Copy any TTF / OTF referenced by @font-face in CSS — for resident-app
# builds we walk every resident's app dir so fonts used by other tiles
# are also bundled.
if [[ "$MACOS_PIPELINE_CACHE" == "0" ]]; then
FONTS_OUT="$RES_DIR/Fonts"
mkdir -p "$FONTS_OUT"
APP_DIRS_FOR_FONTS=()
if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
  d="$(resolve_app_dir "$APP_ID")"
  [[ -n "$d" ]] && APP_DIRS_FOR_FONTS+=("$d")
else
  for id in "${RESIDENT_IDS[@]}"; do
    d="$(resolve_app_dir "$id")"
    [[ -n "$d" ]] && APP_DIRS_FOR_FONTS+=("$d")
  done
fi
for d in "${APP_DIRS_FOR_FONTS[@]}"; do
  node -e "
    const fs = require('fs');
    const path = require('path');
    const appDir = process.argv[1];
    const out = process.argv[2];
    const sharedDirs = process.argv.slice(3);
    function walk(dir) {
      if (!fs.existsSync(dir)) return;
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name === 'node_modules' || entry.name === 'dist') continue;
          walk(full);
        } else if (entry.isFile() && entry.name.endsWith('.css')) {
          const css = fs.readFileSync(full, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
          const re = /@font-face\s*\{([^}]+)\}/gi;
          let m;
          while ((m = re.exec(css)) !== null) {
            const block = m[1];
            const srcMatch = block.match(/src\s*:\s*url\(\s*(?:\"([^\"]+)\"|'([^']+)'|([^)\"']+))\s*\)/i);
            if (!srcMatch) continue;
            const raw = (srcMatch[1] || srcMatch[2] || srcMatch[3] || '').trim();
            if (!raw || /^https?:\/\//i.test(raw) || raw.startsWith('data:')) continue;
            const clean = raw.split(/[?#]/, 1)[0];
            const resolved = path.resolve(path.dirname(full), clean);
            if (!fs.existsSync(resolved)) continue;
            const base = path.basename(resolved);
            const dest = path.join(out, base);
            if (fs.existsSync(dest)) continue;
            fs.copyFileSync(resolved, dest);
            console.log('  copied font:', base);
          }
        }
      }
    }
    walk(appDir);
    for (const dir of sharedDirs) walk(dir);
  " "$d" "$FONTS_OUT" "${GEA_SHARED_COMPONENT_DIRS[@]}"
done

# Per-app window config — the macOS main reads window.json out of Resources/
# at launch to pick up size, transparent title bar, dark appearance, etc.
# Source path is apps/<id>/macos.json so the file lives next to the JSX
# it configures; we copy it as window.json so the runtime path is stable
# regardless of which app id produced it.
APP_DIR_FOR_CONFIG="$(resolve_app_dir "$APP_ID")"
if [[ -n "$APP_DIR_FOR_CONFIG" && -f "$APP_DIR_FOR_CONFIG/macos.json" ]]; then
  cp "$APP_DIR_FOR_CONFIG/macos.json" "$RES_DIR/window.json"
fi
else
  APP_DIRS_FOR_FONTS=()
  APP_DIR_FOR_CONFIG="$(resolve_app_dir "$APP_ID")"
  if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
    [[ -n "$SINGLE_APP_DIR" ]] && APP_DIRS_FOR_FONTS+=("$SINGLE_APP_DIR")
  else
    for id in "${RESIDENT_IDS[@]}"; do
      d="$(resolve_app_dir "$id")"
      [[ -n "$d" ]] && APP_DIRS_FOR_FONTS+=("$d")
    done
  fi
  RESOURCE_SYNC_ARGS=(
    --resources-dir "$RES_DIR"
    --manifest "$BUILD_DIR/resources-owned.json"
    --config-dir "$APP_DIR_FOR_CONFIG"
  )
  for d in "${GEA_SHARED_COMPONENT_DIRS[@]}"; do
    RESOURCE_SYNC_ARGS+=(--shared-css-dir "$d")
  done
  for d in ${APP_DIRS_FOR_FONTS[@]+"${APP_DIRS_FOR_FONTS[@]}"}; do
    RESOURCE_SYNC_ARGS+=(--app-dir "$d")
  done
  RESOURCE_SYNC_RESULT="$(node "$ROOT_DIR/targets/macos/sync-resources.mjs" "${RESOURCE_SYNC_ARGS[@]}")"
  if [[ "$RESOURCE_SYNC_RESULT" == *'changed=1'* ]]; then BUNDLE_CONTENT_CHANGED=1; fi
fi

# Bundle app audio clips (src/sounds/*.{mp3,wav,ogg,m4a}) into Resources/Sounds
# so the native audio host (native-webgl-angle/native/audio_host.mm) can decode
# them by basename out of the app bundle. Runs in both pipeline-cache modes.
SOUNDS_OUT="$RES_DIR/Sounds"
SOUND_APP_DIRS=()
if [[ ${#RESIDENT_IDS[@]} -eq 0 ]]; then
  [[ -n "$SINGLE_APP_DIR" ]] && SOUND_APP_DIRS+=("$SINGLE_APP_DIR")
else
  for id in "${RESIDENT_IDS[@]}"; do
    d="$(resolve_app_dir "$id")"
    [[ -n "$d" ]] && SOUND_APP_DIRS+=("$d")
  done
fi
for d in ${SOUND_APP_DIRS[@]+"${SOUND_APP_DIRS[@]}"}; do
  srcSounds="$d/src/sounds"
  [[ -d "$srcSounds" ]] || continue
  mkdir -p "$SOUNDS_OUT"
  for f in "$srcSounds"/*.mp3 "$srcSounds"/*.wav "$srcSounds"/*.ogg "$srcSounds"/*.m4a; do
    [[ -f "$f" ]] || continue
    dest="$SOUNDS_OUT/$(basename "$f")"
    if [[ ! -f "$dest" ]] || ! cmp -s "$f" "$dest"; then
      cp "$f" "$dest"
      BUNDLE_CONTENT_CHANGED=1
    fi
  done
done

if [[ "$APP_ID" == "gea-companion" ]]; then
  COMPANION_TOOLS_DIR="$RES_DIR/CompanionTools"
  # The scripts belong to the app being built, so they come from its own
  # resolved directory. Composing "<project>/gea-companion/scripts" instead
  # only found them when the project happened to be the folder above the app.
  COMPANION_SCRIPTS_DIR="$(resolve_app_dir "$APP_ID")/scripts"
  mkdir -p "$COMPANION_TOOLS_DIR"
  for d in "$COMPANION_TOOLS_DIR"/*.mjs; do
    [[ -f "$d" ]] || continue
    if [[ ! -f "$COMPANION_SCRIPTS_DIR/$(basename "$d")" ]]; then
      rm -f "$d"
      BUNDLE_CONTENT_CHANGED=1
    fi
  done
  for d in "$COMPANION_SCRIPTS_DIR/"*.mjs; do
    [[ -f "$d" ]] || continue
    RESOURCE_TMP="$COMPANION_TOOLS_DIR/$(basename "$d").tmp.$$"
    cp "$d" "$RESOURCE_TMP"
    if replace_content_stable "$COMPANION_TOOLS_DIR/$(basename "$d")" "$RESOURCE_TMP"; then BUNDLE_CONTENT_CHANGED=1; fi
  done
fi
timing_mark resources

# Ad-hoc sign only after an input changed. The completion stamp is deliberately
# written after codesign so an interrupted resource stage is repaired next run.
CODESIGN_STAMP="$BUILD_DIR/codesign.complete"
CODESIGN_NEEDED="$BUNDLE_CONTENT_CHANGED"
if [[ "$MACOS_PIPELINE_CACHE" == "0" || ! -f "$CODESIGN_STAMP" || ! -d "$APP_BUNDLE/Contents/_CodeSignature" ]]; then
  CODESIGN_NEEDED=1
elif find "$APP_BUNDLE/Contents" -path "$APP_BUNDLE/Contents/_CodeSignature" -prune -o \
       -type f -newer "$CODESIGN_STAMP" -print -quit | grep -q .; then
  CODESIGN_NEEDED=1
fi
if (( CODESIGN_NEEDED != 0 )); then
  rm -f "$CODESIGN_STAMP"
  if ! codesign --force --sign - "$APP_BUNDLE"; then
    echo "Code signing failed for $APP_BUNDLE" >&2
    exit 1
  fi
  touch "$CODESIGN_STAMP"
fi
timing_mark codesign

# A hard-muted runtime verification is eligible to launch only when the
# configured gate source can be traced through its compiler depfile to exactly
# one linked object and the signed executable. The manifest freezes hashes and
# repository revisions; the second invocation re-reads every input, so a stale
# or replaced artifact fails closed without executing application code.
HARD_MUTE_PROVENANCE_FILE="$BUILD_DIR/hard-mute-artifact-provenance.json"
if [[ -n "$MACOS_HARD_MUTE_GATE" ]]; then
  node "$ROOT_DIR/targets/macos/preflight-hard-muted-artifact.mjs" record \
    --manifest "$HARD_MUTE_PROVENANCE_FILE" \
    --executable "$LINK_OUTPUT" \
    --link-signature "$LINK_SIGNATURE_FILE" \
    --source "$MACOS_HARD_MUTE_SOURCE" \
    --gate "$MACOS_HARD_MUTE_GATE" \
    --build-working-directory "$BUILD_INVOCATION_CWD" \
    --dependency-root "$ROOT_DIR" \
    --dependency-root "$GEA_COMPILER" \
    --dependency-root "$GEA_CORE" \
    --dependency-root "$BUILD_INVOCATION_CWD"
  node "$ROOT_DIR/targets/macos/preflight-hard-muted-artifact.mjs" verify \
    --manifest "$HARD_MUTE_PROVENANCE_FILE" \
    --executable "$LINK_OUTPUT" \
    --source "$MACOS_HARD_MUTE_SOURCE" \
    --gate "$MACOS_HARD_MUTE_GATE"
fi
timing_mark hard-mute-preflight

echo "Built $APP_BUNDLE"
if [[ ${#RESIDENT_IDS[@]} -gt 0 ]]; then
  echo "  residents bundled: ${RESIDENT_IDS[*]}"
fi
echo "Run: open '$APP_BUNDLE'"

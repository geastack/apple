#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CXX_BIN="${CXX:-c++}"
BUILD_DIR="${TMPDIR:-/tmp}/gea-ios-root-background-test"

# The two translation units below live in @geastack/engine. Resolve the
# package the way build-macos.sh does. No sibling-checkout fallback: a
# published package has no business guessing where another one was cloned.
GEA_CORE="${GEA_CORE:-$(node -e 'try { process.stdout.write(require("path").dirname(require.resolve("@geastack/core/package.json", { paths: [process.argv[1]] }))) } catch {}' "$ROOT" 2>/dev/null || true)}"
# A path that is not the package is the same as no path: build-macos.sh proves
# it with the package.json, so prove it the same way here rather than failing
# later with a confusing missing-header error.
[ -n "$GEA_CORE" ] && [ -f "$GEA_CORE/package.json" ] || GEA_CORE=""

# Unlike the source-reading tests, this one links framework objects, so there is
# nothing left to check without them.
if [ -z "$GEA_CORE" ]; then
  echo "[test_ios_root_background] skipped: @geastack/core is not resolvable — install this package under an app, check out geastack/core beside this repository, or set GEA_CORE" >&2
  exit 0
fi

GEA_HOST_DIR="${GEA_HOST_DIR:-$GEA_CORE/../host}"
GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-$GEA_CORE/../engine}"
GEA_ELEMENTS_DIR="${GEA_ELEMENTS_DIR:-$GEA_CORE/../elements}"
GEA_GEAOS_PACKAGE_DIR="${GEA_GEAOS_PACKAGE_DIR:-$GEA_CORE/../geaos}"
export GEA_CORE GEA_HOST_DIR GEA_ENGINE_DIR GEA_ELEMENTS_DIR GEA_GEAOS_PACKAGE_DIR

# Include roots come from the framework's own manifest rather than being spelled
# out here: the split scattered what was one tree across core, host, engine,
# elements and geaos, and the manifest is the only authority on where each part
# landed.
# shellcheck source=/dev/null
source "$GEA_CORE/gea_sources.sh"
GEA_FW_INCLUDES=()
while IFS= read -r __inc; do GEA_FW_INCLUDES+=("$__inc"); done < <(gea_fw_include_flags)

mkdir -p "$BUILD_DIR"

# css_atom.cpp is here because tree_state.cpp interns class names through it.
#
# The dead-strip matters: linking is per object file, so core.o arrives with
# `Tree::refreshRequired()` whether or not this test reaches it, and that one
# method references Document, Display and Canvas -- pulling the elements, host
# and platform layers into what is meant to be a four-file unit test. Splitting
# functions into their own sections lets the linker drop what nothing calls, so
# the TU list stays the unit under test rather than the whole framework. Apple's
# ld spells this `-dead_strip`; this target only ever builds on macOS.
"$CXX_BIN" -std=c++20 \
  -ffunction-sections -fdata-sections -Wl,-dead_strip \
  "${GEA_FW_INCLUDES[@]}" \
  "$GEA_ENGINE_DIR/ui/core.cpp" \
  "$GEA_ENGINE_DIR/ui/tree_state.cpp" \
  "$GEA_ENGINE_DIR/ui/css_atom.cpp" \
  "$ROOT/targets/ios/main/ios_root_background.cpp" \
  "$ROOT/targets/ios/test/test_ios_root_background_main.cpp" \
  -o "$BUILD_DIR/test_ios_root_background"

"$BUILD_DIR/test_ios_root_background"

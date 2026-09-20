#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# What the assertions below read lives in @geastack/core and its sibling
# packages. Resolve it the way build-macos.sh does, then fall back to a
# checkout beside this repository -- node resolution only succeeds when this
# package is installed under an app's node_modules.
GEA_CORE="${GEA_CORE:-$(node -e 'try { process.stdout.write(require("path").dirname(require.resolve("@geastack/core/package.json", { paths: [process.argv[1]] }))) } catch {}' "$ROOT" 2>/dev/null || true)}"
# A path that is not the package is the same as no path: build-macos.sh proves
# it with the package.json, so prove it the same way here rather than failing
# later with a confusing missing-header error.
[ -n "$GEA_CORE" ] && [ -f "$GEA_CORE/package.json" ] || GEA_CORE=""

# Include roots come from the framework's own manifest rather than being spelled
# out here: the split scattered what was one `lib/gea-embedded/` tree across
# core, host, engine, elements and geaos, and the manifest is the only authority
# on where each part landed.
GEA_FW_INCLUDES=()
# Defined even when core is absent: the skipped assertions below still expand
# this path to build their arguments, before the skip is decided.
GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-}"
if [ -n "$GEA_CORE" ]; then
  GEA_HOST_DIR="${GEA_HOST_DIR:-$GEA_CORE/../host}"
  GEA_ENGINE_DIR="${GEA_ENGINE_DIR:-$GEA_CORE/../engine}"
  GEA_ELEMENTS_DIR="${GEA_ELEMENTS_DIR:-$GEA_CORE/../elements}"
  GEA_GEAOS_PACKAGE_DIR="${GEA_GEAOS_PACKAGE_DIR:-$GEA_CORE/../geaos}"
  export GEA_CORE GEA_HOST_DIR GEA_ENGINE_DIR GEA_ELEMENTS_DIR GEA_GEAOS_PACKAGE_DIR
  # shellcheck source=/dev/null
  source "$GEA_CORE/gea_sources.sh"
  while IFS= read -r __inc; do GEA_FW_INCLUDES+=("$__inc"); done < <(gea_fw_include_flags)
fi

CXX_BIN="${CXX:-c++}"
BUILD_DIR="${TMPDIR:-/tmp}/gea-ios-native-text-input-test"

mkdir -p "$BUILD_DIR"

require_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "[test_ios_native_text_input] $message" >&2
    return 1
  fi
}

reject_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "[test_ios_native_text_input] $message" >&2
    return 1
  fi
}

# Assertions that read framework source rather than this repository's. They are
# the only ones that need a resolvable @geastack/core, so without one they skip
# and the iOS-side assertions still run.
require_framework_source() {
  if [ -z "$GEA_CORE" ]; then
    echo "[test_ios_native_text_input] skipped (@geastack/core not resolvable): $3" >&2
    return 0
  fi
  require_source "$@"
}

require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "@interface GeaNativeInputField : UITextField" \
  "ios_main.mm should materialize inputs as native UITextField controls"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "UIControlEventEditingChanged" \
  "native iOS input fields should dispatch editing changes"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "PointerEventType::Input" \
  "native iOS input fields should forward input events into the framework"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "becomeFirstResponder" \
  "native iOS input fields should become first responder for the system keyboard"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "Tree::instance().setActiveInput(_nodeId)" \
  "native iOS input focus should update the framework active input"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "field.backgroundColor = node.style.has_bg" \
  "native iOS input fields should receive input background styles"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "field.layer.borderWidth" \
  "native iOS input fields should receive input border styles"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "field.layer.cornerRadius" \
  "native iOS input fields should receive input border radius"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "#include \"font_registry.h\"" \
  "native iOS input fields should use the UIKit font registry"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "gea::ios::fontForId(node.style.font_id, fontSize)" \
  "native iOS input fields should resolve framework font ids to UIKit fonts"
reject_source "$ROOT/targets/ios/main/ios_main.mm" \
  "if (!field.isFirstResponder &&" \
  "focused native iOS input fields should still sync controlled value changes from the framework tree"
require_source "$ROOT/targets/ios/main/font_registry.mm" \
  "FontRegistry::familyName(fontId)" \
  "iOS UIKit fonts should resolve generated font-family ids back to family names"
require_source "$ROOT/targets/ios/main/font_registry.mm" \
  "CTFontManagerRegisterFontsForURL" \
  "iOS should register bundled TTF/OTF resources before resolving custom fonts"
require_framework_source "$GEA_CORE/include/graphics/font.h" \
  "static const char *familyName(int familyId);" \
  "the framework font registry should expose generated family names for native targets"
require_framework_source "$GEA_CORE/scripts/generate-gea-embedded-fonts.mjs" \
  "lookupFontFamilyName" \
  "generated font tables should include a family-id to family-name lookup"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "fontResources" \
  "iOS project generation should copy font files into the app bundle"
require_framework_source "$GEA_ENGINE_DIR/ui/render.cpp" \
  "isNativeTextInputView" \
  "native input targets should identify input views before recording pixels"
require_framework_source "$GEA_ENGINE_DIR/ui/render.cpp" \
  "if (overlaps_clip && !nativeTextInput)" \
  "native input targets should not record input view pixels"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "GEA_EMBEDDED_ENABLE_NATIVE_TEXT_INPUT=1" \
  "iOS builds should enable native text input"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "GEA_EMBEDDED_ENABLE_VIRTUAL_KEYBOARD=0" \
  "iOS builds should disable the framework virtual keyboard"

if [ -n "$GEA_CORE" ]; then
  "$CXX_BIN" -std=c++20 \
    -DGEA_EMBEDDED_ENABLE_NATIVE_TEXT_INPUT=1 \
    "${GEA_FW_INCLUDES[@]}" \
    -c "$GEA_ENGINE_DIR/ui/render.cpp" \
    -o "$BUILD_DIR/render-native-input.o"
else
  echo "[test_ios_native_text_input] skipped (@geastack/core not resolvable): framework render.cpp compile" >&2
fi

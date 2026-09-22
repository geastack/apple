#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# What the one framework assertion below reads lives in @geastack/core.
# Resolve it the way build-macos.sh does, then fall back to a checkout beside
# this repository -- node resolution only succeeds when this package is
# installed under an app's node_modules.
GEA_CORE="${GEA_CORE:-$(node -e 'try { process.stdout.write(require("path").dirname(require.resolve("@geastack/core/package.json", { paths: [process.argv[1]] }))) } catch {}' "$ROOT" 2>/dev/null || true)}"
# A path that is not the package is the same as no path: build-macos.sh proves
# it with the package.json, so prove it the same way here rather than failing
# later with a confusing missing-header error.
[ -n "$GEA_CORE" ] && [ -f "$GEA_CORE/package.json" ] || GEA_CORE=""

require_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "[test_ios_native_view_renderer] $message" >&2
    return 1
  fi
}

# The one assertion that reads framework source rather than this repository's.
# Without a resolvable @geastack/core it skips and the iOS-side assertions still
# run.
require_framework_source() {
  if [ -z "$GEA_CORE" ]; then
    echo "[test_ios_native_view_renderer] skipped (@geastack/core not resolvable): $3" >&2
    return 0
  fi
  require_source "$@"
}

reject_source() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "[test_ios_native_view_renderer] $message" >&2
    return 1
  fi
}

assert_max_lines() {
  local file="$1"
  local max_lines="$2"
  local message="$3"
  local line_count
  line_count="$(wc -l < "$file" | tr -d ' ')"
  if (( line_count > max_lines )); then
    echo "[test_ios_native_view_renderer] $message: $file has $line_count lines, max $max_lines" >&2
    return 1
  fi
}

assert_max_lines "$ROOT/targets/ios/main/ios_renderer.mm" 300 \
  "iOS renderer files should stay in focused chunks"
for renderer_file in "$ROOT"/targets/ios/main/renderer/*.h "$ROOT"/targets/ios/main/renderer/*.mm; do
  assert_max_lines "$renderer_file" 300 \
    "iOS renderer files should stay in focused chunks"
done
require_source "$ROOT/targets/ios/main/ios_renderer.h" \
  "class IosRenderer" \
  "iOS should expose a native UIView renderer entrypoint"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "makeViewForType" \
  "iOS should materialize GEA nodes as UIKit views"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "case NodeType::View" \
  "iOS should translate view/div nodes into UIView instances"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "case NodeType::Text" \
  "iOS should translate text nodes into native labels"
require_source "$ROOT/targets/ios/main/renderer/ios_renderer_internal.h" \
  "GeaNativeButton : UIButton" \
  "iOS should translate button nodes into native UIButtons"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "case NodeType::Button: return [view isKindOfClass:[GeaNativeButton class]];" \
  "iOS should not treat button nodes as generic UIView containers"
require_source "$ROOT/targets/ios/main/renderer/native_label.mm" \
  "geaUseBitmapFont" \
  "iOS native text should preserve the runtime bitmap-font fallback"
require_source "$ROOT/targets/ios/main/renderer/native_label.mm" \
  "sizeThatFits:CGSizeMake(CGFLOAT_MAX" \
  "iOS native button labels should use UIKit text metrics to avoid clipping"
require_source "$ROOT/targets/ios/main/renderer/native_label.mm" \
  "label.superview isKindOfClass:[GeaNativeButton class]" \
  "iOS native button label fitting should only apply inside native buttons"
require_source "$ROOT/targets/ios/main/renderer/native_label.mm" \
  "label.hidden = label.geaHostedByNativeButtonTitle" \
  "iOS should hide duplicate child labels when UIButton owns the visible title"
require_source "$ROOT/targets/ios/main/renderer/native_button.mm" \
  "setAttributedTitle" \
  "iOS native buttons should render text through UIButton title layout"
require_source "$ROOT/targets/ios/main/font_registry.mm" \
  "extern \"C\" bool gea_host_measure_text" \
  "iOS layout should use native UIKit text metrics"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "case NodeType::Canvas" \
  "iOS should keep canvas nodes on a raster-backed native view"
require_framework_source "$GEA_CORE/include/graphics/font.h" \
  "lookupFontFamilyName" \
  "the framework font registry should expose font-family names for native host renderers"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "syncRecursive" \
  "iOS native renderer should reconcile the full mounted tree"
require_source "$ROOT/targets/ios/main/renderer/view_reconciler.mm" \
  "parentAbsYForChildren = node.layout.y - tree.scrollTop(nodeId)" \
  "iOS native scroll children should be laid out in UIScrollView content coordinates"
require_source "$ROOT/targets/ios/main/renderer/native_scroll_container.mm" \
  "GEA_IOS_SCROLL_DEBUG_MARKERS" \
  "iOS native scroll should expose opt-in numeric rubber-band telemetry markers"
require_source "$ROOT/targets/ios/main/renderer/native_scroll_container.mm" \
  "minObservedContentOffsetY" \
  "iOS native scroll telemetry should record the raw overscroll extrema"
require_source "$ROOT/targets/ios/main/renderer/native_scroll_container.mm" \
  "rawY=" \
  "iOS native scroll telemetry should report unclamped native contentOffset values"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "GeaIosRubberBandUITests" \
  "iOS project generation should include the rubber-band telemetry XCUITest target"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "GCC_ENABLE_OBJC_EXCEPTIONS = YES;" \
  "iOS project generation should enable Objective-C exceptions so native framework throws can be caught"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  'COMPILER_FLAGS = "-fobjc-exceptions";' \
  "iOS project generation should pass the Objective-C exception flag to Objective-C++ compilation"
reject_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "OTHER_CPLUSPLUSFLAGS" \
  "iOS project generation should not pass Objective-C exception flags to plain C++ sources"
require_source "$ROOT/targets/ios/test/GeaIosRubberBandUITests.swift" \
  "minRawY" \
  "iOS rubber-band UI tests should assert top-edge raw overscroll numerically"
require_source "$ROOT/targets/ios/test/GeaIosRubberBandUITests.swift" \
  "maxRawY" \
  "iOS rubber-band UI tests should assert bottom-edge raw overscroll numerically"
reject_source "$ROOT/targets/ios/main/ios_main.mm" \
  "GeaNativeScrollView" \
  "iOS should not keep the legacy pixel-buffer native scroll shim"
reject_source "$ROOT/targets/ios/main/ios_main.mm" \
  "visualBounceY" \
  "iOS should not emulate rubber-band bounce by shifting pixel-buffer crops"
reject_source "$ROOT/targets/ios/main/ios_main.mm" \
  "drawNativeScrollBounceOverlaysWithImage" \
  "iOS should not draw custom rubber-band bounce overlays"
require_source "$ROOT/targets/ios/main/ios_main.mm" \
  "gea::ios::IosRenderer::instance().sync" \
  "iOS app tick should sync UIKit views after running the GEA frame"
require_source "$ROOT/targets/ios/main/canvas_view.mm" \
  "Tree::instance().canvas" \
  "iOS canvas view should render explicit canvas node buffers"
require_source "$ROOT/targets/ios/main/image_bridge.mm" \
  "UIImage *imageForId" \
  "iOS renderer should bridge GEA image nodes to UIImage"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "ios_renderer.mm" \
  "iOS Xcode project generation should compile the native renderer"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "renderer/native_button.mm" \
  "iOS Xcode project generation should compile split renderer controls"
require_source "$ROOT/targets/ios/generate-xcode-project.mjs" \
  "renderer/view_reconciler.mm" \
  "iOS Xcode project generation should compile split renderer reconciliation"

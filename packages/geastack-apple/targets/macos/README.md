# macOS target

Build a Gea app as a native Cocoa Mac app — `<Button>` becomes
`NSButton`, `<Text>` becomes `NSTextField`, `<View>` becomes `NSView`,
`<Image>` becomes `NSImageView`, `<canvas>` is a custom `NSView` backed by
CoreGraphics, `<virtual-list>` is `NSScrollView`. The flex layout engine
in `@geastack/engine`'s `ui/layout.cpp` computes frames; AppKit draws.

## Build

The app needs `@geastack/apple` and `@geastack/cli` in its dependencies and
`"macos": true` under `gea.targets` in its `package.json`. From the app folder:

    npx gea run --target macos

builds the app and opens it. `npx gea build --target macos` builds only; the
bundle is `dist/macos/<app-id>/<AppName>.app`. `gea run --target macos` needs
`@geastack/cli` 0.1.117 or later; with an older CLI, build and then
`open dist/macos/<app-id>/<AppName>.app`.

`gea build --target macos` runs this package's `build-macos.sh <app-id>` with
the app's build configuration. The script can also be run directly from the
app folder as `node_modules/@geastack/apple/targets/macos/build-macos.sh
<app-id>`.

## Where the build writes

Everything this target produces lands under the **app project** being built,
never under this package: `<app>/dist/macos/<app-id>/<AppName>.app` for the
bundle, `<app>/dist/macos/<app-id>/build/` for objects and PCHs, and
`<app>/dist/macos/.generated/<app-id>/` for the generated C++. The app is the
directory the build runs in: `gea build` runs this script in the app, and a
direct run uses the invocation directory.

Output does not go under the package because the package lives in the app's
`node_modules`, which npm replaces on reinstall. Set `GEA_MACOS_OUTPUT_DIR` to
put the whole tree elsewhere.

The build compiles the app's entry through geatsc into
`dist/macos/.generated/<app-id>/` and links the generated C++ into the bundle;
a geatsc failure for a resolved app fails the build. Only when `<app-id>`
resolves to no app with an entry file does the build fall back to the built-in
smoke app (`main/macos_smoke_app.cpp`), which exercises View / Text / Button /
event dispatch.

## Hard-muted builds

Setting `GEA_MACOS_HARD_MUTE_SOURCE` (absolute path to the committed native
audio source) and `GEA_MACOS_HARD_MUTE_GATE` (the mute literal it contains)
together makes the build record and check that the signed executable was built
from that source with the gate present. It writes
`dist/macos/<app-id>/build/hard-mute-artifact-provenance.json`;
`preflight-hard-muted-artifact.mjs verify` re-checks a binary against it
without launching it. Setting only one of the two variables is an error.

## Architecture

    JSX (or smoke C++) → Document / Tree mutations → Tree::computeLayout
      → MacosRenderer::sync (walks the laid-out tree)
        → ensureViewForNode dispatches on NodeType
          → NSView / NSTextField / NSButton / NSImageView / GeaCanvasView
            / NSScrollView
          → applyViewStyle (frame, background, border, cornerRadius,
            opacity, rotation, masksToBounds)
          → applyTypeSpecificProps (per-type content)

The display-list pipeline (`ui/render.cpp`, `ui/dirty_regions.cpp`) is
bypassed on this target — AppKit owns its own invalidation. The
custom touch/momentum code in `ui/input.cpp` is bypassed too;
NSClickGestureRecognizer (on Views/anything with a pressId) and
NSButton target/action dispatch Click+Press events back into
`Tree::dispatchEvent`. NSScrollView gives VirtualList native momentum
and elastic boundaries.

The only intrusive change to the framework is `Tree::computeLayout`
(peer of `refresh`) — it runs just the flex pass without building a
display list, so other targets keep calling `refresh()` unchanged.

## Frame loop

`main/macos_main.mm` drives frames from the window's `CADisplayLink` on
macOS 14 and later, at the screen's maximum refresh rate (following the window
between displays). On older macOS, or when the app's window config sets
`"vsync": false`, it uses a fast `NSTimer` instead; with `vsync: false` frames
run uncapped. Both are scheduled on `NSRunLoopCommonModes` so the loop keeps
firing during live window-resize and other event-tracking modes. The window
config is `macos.json` in the app folder overlaid with
`gea.targets.macos.window` from its `package.json` (`width`, `height`,
`vsync`, `fullscreen`, ...), bundled as `Resources/window.json`. Each tick:

1. `Application::frame(timestampMs)` lets the app update state
2. Force `style.width/height` on the mounted root to the current window
   content size — this is the macOS convention that makes the root
   viewport track resize automatically
3. `Tree::computeLayout(root, w, h)`
4. `MacosRenderer::sync(rootView, root)`

## Verification stub

Running with `GEA_MACOS_VERIFY_ONCE=1` logs the tree, NSView hierarchy,
fires a press on the first Button node twice, then exits. Useful for
quick regression checks after changes to the renderer.

## What works / what's stubbed

Native: View / Text / Button / Image / Canvas / VirtualList; flex
layout; click + press events; trackpad-momentum scroll; window resize
(live + final); standard menu bar with Cmd-Q.

Audio: `targets/shared/apple_audio.mm` (shared with iOS) backs
`gea::platform::audio` with AVAudioEngine — sample-accurately scheduled,
mixed oscillators on an `AVAudioSourceNode`, plus `playFile`/`playPcm` on
`AVAudioPlayerNode`s. `targets/shared/build-audio-selftest.sh` builds and
runs the measurement harness (offline render, RMS + measured frequency);
`GEA_AUDIO_CAPTURE_RAW=<path>` captures an app run for
`targets/shared/analyze-audio-capture.mjs`.

Also implemented in `main/`: HTTP(S) `fetch` over `NSURLSession`
(`macos_network.mm`), battery level from IOKit power sources and pointer
input as touch (`macos_sensors.cpp`), timers (`macos_timers.mm`), launching
other apps' bundles (`macos_app_platform.mm`), and the `runDeviceCommand`
shell escape hatch (`macos_device_control.mm`).

Stubbed in `main/macos_sensors.cpp`: the accelerometer/gyroscope (tilt 0,
gravity on Z) and the embedded memory diagnostics (all zeros).
`main/macos_display.mm` keeps the framebuffer display inert because AppKit
draws. `main/` has no WiFi or Bluetooth backend. Code signing with
entitlements and notarisation are not done by the build; development bundles
are signed ad hoc.

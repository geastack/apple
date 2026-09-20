# macOS target

Build a gea-embedded app as a native Cocoa Mac app — `<Button>` becomes
`NSButton`, `<Text>` becomes `NSTextField`, `<View>` becomes `NSView`,
`<Image>` becomes `NSImageView`, `<canvas>` is a custom `NSView` backed by
CoreGraphics, `<virtual-list>` is `NSScrollView`. The flex layout engine
in `@geastack/engine`'s `ui/layout.cpp` computes frames; AppKit draws.

## Build

    targets/macos/build-macos.sh <app-id>
    open dist/macos/<app-id>/<AppName>.app

## Where the build writes

Everything this target produces lands under the **app project** being built,
never under this package: `<app>/dist/macos/<app-id>/<AppName>.app` for the
bundle, `<app>/dist/macos/<app-id>/build/` for objects and PCHs, and
`<app>/dist/macos/.generated/<app-id>/` for the generated C++. The app is the
directory the build runs in: `gea build` runs this script in the app, and a
direct run uses the invocation directory.

This package is installed into an app's `node_modules`, so a package-relative
output path hid every build inside a directory nobody opens and npm deletes on
the next install. Set `GEA_MACOS_OUTPUT_DIR` to put the whole tree elsewhere.

`<app-id>` is currently any name; when no generated app is present under
`dist/macos/.generated/<app-id>/` the build falls back to a built-in
Phase B smoke app (`macos_smoke_app.cpp`) that exercises View / Text /
Button / event dispatch. Real geatsc-compiled apps drop into
`dist/macos/.generated/` and supersede the smoke automatically — the
JSX → C++ pipeline for the macOS target is a follow-up.

## Hard-muted builds must prove artifact provenance

For any verification that must not produce audio, configure the final native
mute source and its literal on the build itself:

```sh
GEA_MACOS_HARD_MUTE_SOURCE=/absolute/path/to/the/committed/native/audio_source.mm \
GEA_MACOS_HARD_MUTE_GATE=THE_NATIVE_MUTE_ENVIRONMENT_LITERAL \
targets/macos/build-macos.sh <app-id>
```

Both variables are required together. After code signing, the build writes
`dist/<app-id>/build/hard-mute-artifact-provenance.json` and statically proves:

- the selected source is the committed blob at the recorded dependency revision;
- exactly one linked object depends on that source and contains the gate;
- `link.sig` records that exact object;
- source, translation unit, depfile, link signature, object, and executable
  SHA-256 values still match; and
- the signed executable contains the same gate.

Immediately before launch, rerun the no-launch check against the exact binary:

```sh
node targets/macos/preflight-hard-muted-artifact.mjs verify \
  --manifest /absolute/path/to/build/hard-mute-artifact-provenance.json \
  --executable "/absolute/path/to/App.app/Contents/MacOS/App" \
  --source /absolute/path/to/the/committed/native/audio_source.mm \
  --gate THE_NATIVE_MUTE_ENVIRONMENT_LITERAL
```

Do not launch unless this prints
`PASS artifact-static-hard-mute-gate=present`. The checker reads files and Git
metadata only; it does not execute the app or open an audio device. Any missing
manifest, gate, changed dependency revision, or changed source/object/executable
fails closed.

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

`macos_main.mm` schedules a 60Hz `NSTimer` on `NSRunLoopCommonModes` so
the loop keeps firing during live window-resize and other event-
tracking modes. Each tick:

1. `gea_embedded_app_frame(timestampMs)` lets the app update state
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

Audio is real: `targets/shared/apple_audio.mm` (shared with iOS) backs
`gea::platform::audio` with AVAudioEngine — sample-accurately scheduled,
mixed oscillators on an `AVAudioSourceNode`, plus `playFile`/`playPcm` on
`AVAudioPlayerNode`s. `targets/shared/build-audio-selftest.sh` builds and
runs the measurement harness (offline render, RMS + measured frequency);
`GEA_AUDIO_CAPTURE_RAW=<path>` captures a real app run for
`targets/shared/analyze-audio-capture.mjs`.

Stubbed for v1: WiFi (`macos_wifi`), BLE (`macos_ble`), IMU (`macos_imu`)
— present only as link-satisfying no-ops; apps that depend on these will
run but those calls return inert values. Custom font bundling, code
signing with entitlements, notarisation, and the JSX → C++ pipeline for
this target are follow-ups.

# watchOS target

Build a gea-embedded JSX app as a watch-only Apple Watch app.

From an app that depends on `@geastack/apple` and declares
`gea.targets.watchos`, the CLI drives this target:

```bash
npx gea build --target watchos                 # simulator .app, no launch
npx gea build --target watchos --mode device   # watchos .app (unsigned without a team)
npx gea run --target watchos                   # build, install and launch on a watch simulator
npx gea run --target watchos --mode device     # build, sign, install and launch on a watch
```

The CLI runs `build-watchos.sh <app-id> simulator|device` from the app folder;
the script can be run directly the same way. Either way it needs a
`@geastack/cli` with watchOS support, which also builds the app icon
(`gea apps apple-icons --platform watchos`).

`counter-jsx` in the examples repository is the reference app for this target.

The script resolves `@geastack/core`, `@geastack/compiler` and `@geastack/cli`
by walking up `node_modules` from the app folder, as the iOS script does. Output
goes to `<app>/dist/watchos` (override with `GEA_WATCHOS_OUTPUT_DIR`); the Xcode
project is generated at `<app>/dist/watchos/<app-id>/GeaWatch.xcodeproj`. Do not
hand-edit it.

## How it renders

watchOS gives an app no UIView hierarchy, so there is no native view renderer
like iOS has. The shell is a SwiftUI app (`main/watchos_app.swift`): gea lays
out and paints the whole UI into its RGBA8888 framebuffer, and the shell shows
each presented frame as an image covering the screen. Touches come back through
a drag gesture as gea touch events. Turning the Digital Crown scrolls the
first vertical scroll container, as the Up/Down buttons do on touchless boards;
`GeaWatchHost.crownPointsPerUnit` sets how far it moves. The Crown's range is
that container's scroll range, so the system Crown indicator shows the scroll
position, however the list was scrolled. The frame loop runs at 60 Hz while the app
is active and stops when the watch dims or the app goes to the background.

The C++ side (`main/watchos_host.mm`) reuses the iOS host backends for the
framebuffer, frame clock, allocator, touch state, CoreMotion and AVAudioEngine
audio, and drives CSS and `data-anim` animations each frame as the embedded
runtime loop does. `main/watchos_platform.mm` adds what is different on a
watch: battery level, charging state and haptics come from WatchKit, and the
camera reports itself unavailable, so camera apps build and a `<camera>`
renders nothing.

## Sizing

The canvas is the panel's physical pixels. One CSS `px` is 1.5 physical pixels
by default, the ratio the ESP32 watch boards with the same panels (368x448,
410x502) declare, so an app is the same size on either. That makes a 46mm watch
277x331 CSS px and a 40mm SE 216x263. An app picks its own ratio with
`gea.targets.watchos.cssDevicePixelRatio` (an object target) or
`gea.cssDevicePixelRatio`; `GEA_WATCHOS_CSS_DEVICE_PIXEL_RATIO` overrides both
for one build. Font atlases are baked at the same ratio.

The canvas covers the whole screen, including the area under the system clock.
watchOS's safe area keeps about a fifth of the screen free at the top and
another at the bottom, which is too much to give up on a watch. Apps that need
the clock area clear lay themselves out around it, using the insets the shell
publishes as `:root` custom properties, in CSS px, measured for the watch it
runs on:

| Property | Meaning |
| --- | --- |
| `--gea-safe-top` | clears the system clock |
| `--gea-safe-left`, `--gea-safe-right` | how far the rounded corners cut in at that depth |
| `--gea-safe-bottom` | where the bottom corners cut in no further than the sides |
| `--gea-screen-radius` | how deep the corner curve runs |

Other targets don't set them, so read them with a fallback:
`padding-top: var(--gea-safe-top, 4px)`. The values come from a table in
`main/watchos_host.mm`, one row per panel size: corners from each Simulator
device type's `framebufferMask`, the clock measured from a blank app. A watch
with a new panel size gets the nearest row, scaled by height, until it has its
own.

## Limits

- Runtime `gea` apps only. Apple SDK bindings (`@geastack/apple/UIKit` and the
  rest) are not available: they drive UIKit views, and the build compiles with
  `--no-apple-native`.
- No text input or virtual keyboard.
- Apps with their own ESP32 native code (`diagnostics`, `e-reader`,
  `gea3d-cube`, `gea-bench`, `ttf-bench`), GPIO hardware (`headless-led`) or a
  board-specific bitmap font (`m5-stopwatch`) do not build here.
- Only 40mm and larger watches are tested. Fixed-pixel layouts drawn for 245x299 (such as
  `counter-jsx`) clip slightly on the 40mm SE.

## Simulator and device

The simulator path picks a booted Apple Watch simulator, otherwise an Apple
Watch Series model. Set `GEA_WATCHOS_SIMULATOR_UDID` to choose one, and
`GEA_WATCHOS_OPEN_SIMULATOR=0` to leave the simulator window (Simulator.app, or DeviceHub.app on Xcode 27) closed.

Device builds go through the paired iPhone. Name the watch with
`GEA_WATCHOS_DEVICE_ID` (from `xcrun devicectl list devices`) and the team with
`GEA_WATCHOS_DEVELOPMENT_TEAM` (`GEA_IOS_DEVELOPMENT_TEAM` and Xcode's last
selected team also work):

```bash
GEA_WATCHOS_DEVICE_ID=<id> GEA_WATCHOS_DEVELOPMENT_TEAM=ABCDE12345 npx gea run --target watchos --mode device
```

`gea build --target watchos --mode device` without a team builds an unsigned
`watchos` binary, which is enough to check that the app compiles for hardware.

## Test

`test/run-watchos-counter-ui-test.sh <path/to/examples/apps/counter-jsx>` builds
the counter for a watch simulator and runs `GeaWatchCounterUITests`. The test
checks that tapping `+` repaints the counter and that a tap on empty background
changes nothing. The test files only exist in a checkout of this repository. The
generator adds the UI-test target when it finds them.

# GeaStack Apple

Native Apple target support for GeaStack.

This repo contains the packages and target templates that let Gea applications
run as native Apple apps instead of browser views. The current focus is iOS and
macOS application shells, generated Apple SDK bindings, and experimental native
JSX/SwiftUI helpers.

## What Is Here

| Path | Purpose |
| --- | --- |
| `packages/geastack-apple` | Generated Apple framework type declarations and runtime module stubs for Foundation, UIKit, AppKit, Metal, MapKit, AVFoundation, and related SDKs. |
| `packages/geajs-apple-swiftui` | Optional JSX-to-SwiftUI source helpers for Apple-native experiments. |
| `packages/geatsc-plugin-apple-native` | `geatsc` plugin metadata for Apple-native bindings. |
| `packages/geastack-apple/targets/ios` | UIKit target template, Xcode project generator, simulator/device build script, and iOS tests. |
| `packages/geastack-apple/targets/macos` | Cocoa/AppKit target template, generated resident-app registry, and macOS build script. |

## Quick Start

The build scripts run in the directory of the app you are building, which is
where npm installed this package. From an app that depends on `@geastack/apple`:

```sh
npx gea build --target ios            # or: node_modules/@geastack/apple/targets/ios/build-ios.sh <app-id> simulator
npx gea run --target ios              # build, then install and launch on an iPhone simulator
```

Build a signed device app:

```sh
GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 npx gea run --target ios --mode device
```

Build a macOS app:

```sh
npx gea build --target macos          # or: node_modules/@geastack/apple/targets/macos/build-macos.sh <app-id>
open dist/macos/<app-id>/<AppName>.app
```

Build the Apple TypeScript helper packages from their package folders:

```sh
npm run build
npm run typecheck
```

## Dependencies

- Xcode with iOS and macOS SDKs.
- Xcode command line tools.
- An installed iOS Simulator runtime for simulator runs.
- A configured Apple development team for signed device runs.
- The rest of the stack comes from npm: an app that depends on
  `@geastack/apple` gets `@geastack/core`, `@geastack/compiler` and the other
  siblings installed alongside it, and the build scripts resolve them there.

## Documentation

- [packages/geastack-apple/targets/ios/README.md](packages/geastack-apple/targets/ios/README.md):
  iOS simulator and device build details.
- [packages/geastack-apple/targets/macos/README.md](packages/geastack-apple/targets/macos/README.md):
  macOS renderer and target architecture.

## How This Fits The Stack

Apple targets consume compiled Gea apps and map Gea primitives onto native
platform controls where possible. They are not the generic compiler, not the
embedded hardware backend, and not the public website. This repo is the Apple
platform adapter layer: it owns native shells, generated SDK binding surfaces,
and Apple-specific target build scripts.

## License

Apache-2.0 (see `LICENSE`). Use it, change it, ship closed-source products on
it, no strings attached. The only GeaStack code under a different license is
the embedded board support (`targets` and `@geastack/chips`, GPL-3.0-only):
shipping closed-source firmware through those needs a commercial license.
Contact [contact@geastack.com](mailto:contact@geastack.com) for commercial terms, support and hosted builds.

## Maintenance Notes

- Do not hand-edit generated Xcode projects under target build directories.
  Change the generator scripts instead.
- Keep Apple SDK binding packages source-compatible with the `geatsc` plugin
  that consumes their metadata.
- Keep smoke apps small. They exist to prove renderer and event plumbing before
  a generated Gea app is available.
- When adding target behavior, update the target README in the same change.

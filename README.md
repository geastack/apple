# GeaStack Apple

Native Apple target support for GeaStack.

This repo contains the packages and target templates that let Gea applications
run as native Apple apps instead of browser views. The current focus is iOS, tvOS and
macOS application shells, generated Apple SDK bindings, and experimental native
JSX/SwiftUI helpers.

## What Is Here

| Path | Purpose |
| --- | --- |
| `packages/geastack-apple` | Generated Apple framework type declarations and runtime module stubs for Foundation, UIKit, AppKit, Metal, MapKit, AVFoundation, and related SDKs. |
| `packages/geajs-apple-swiftui` | Optional JSX-to-SwiftUI source helpers for Apple-native experiments. |
| `packages/geatsc-plugin-apple-native` | `geatsc` plugin metadata for Apple-native bindings. |
| `packages/vite-plugin-apple-native` | Vite plugin that lowers JSX written against UIKit/AppKit view tags into native view construction, for apps that render through Apple views. |
| `packages/geastack-apple/targets/ios` | UIKit target template (iOS and tvOS), Xcode project generator, simulator/device build script, and iOS tests. |
| `packages/geastack-apple/targets/macos` | Cocoa/AppKit target template, generated resident-app registry, and macOS build script. |

## Quick Start

The build scripts run in the directory of the app you are building, which is
where npm installed this package. The app needs `@geastack/apple` and the
`gea` CLI (`@geastack/cli`; tvOS needs 0.1.110 or later) in its own
dependencies — `npx gea` does not fetch the CLI on demand — and must declare
each Apple target it builds for in the `gea` block of its `package.json`.
An app created with `npx create-geastack my-app --targets ios,tvos,macos`
already has all three.

```sh
npm install @geastack/apple
npm install --save-dev @geastack/cli
```

```json
"gea": {
  "id": "my-app",
  "entry": "index.tsx",
  "targets": { "ios": true, "tvos": true, "macos": true }
}
```

From the app folder:

```sh
npx gea build --target ios            # simulator .app, no launch
npx gea run --target ios              # build, then install and launch on an iPhone simulator
npx gea run --target tvos             # the same UIKit host on an Apple TV simulator
```

Build a signed device app:

```sh
GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 npx gea run --target ios --mode device
```

Build a macOS app:

```sh
npx gea build --target macos
open dist/macos/<app-id>/<AppName>.app
```

The CLI runs `targets/ios/build-ios.sh` and `targets/macos/build-macos.sh`
from the installed package with the app's build configuration
(`gea.targets.<target>.build` and the geatsc plugins its dependencies
provide). The scripts
can also be run directly from the app folder, for example
`node_modules/@geastack/apple/targets/ios/build-ios.sh <app-id> simulator`,
but then that configuration is not applied, and `build-ios.sh` also boots,
installs and launches the app unless `GEA_IOS_SKIP_LAUNCH=1` is set — it
behaves like `gea run`, not `gea build`.

Build the TypeScript packages (`geastack-apple`, `geajs-apple-swiftui`,
`geatsc-plugin-apple-native`) from their package folders.
`vite-plugin-apple-native` is plain JavaScript and has no build step.

```sh
npm run build
npm run typecheck
```

## Dependencies

- Xcode with the iOS, tvOS and macOS SDKs (whichever you target).
- Xcode command line tools.
- An installed iOS or tvOS Simulator runtime for simulator runs.
- A configured Apple development team for signed device runs.
- The rest of the stack comes from npm: an app that depends on
  `@geastack/apple` gets `@geastack/core`, `@geastack/compiler` and the other
  siblings installed alongside it, and the build scripts resolve them there.
  `@geastack/cli` is not among them: install it in the app as well (Node 22
  or later).

## Documentation

- [packages/geastack-apple/targets/ios/README.md](packages/geastack-apple/targets/ios/README.md):
  iOS and tvOS simulator and device build details.
- [packages/geastack-apple/targets/macos/README.md](packages/geastack-apple/targets/macos/README.md):
  macOS renderer and target architecture.

## How This Fits The Stack

Apple targets consume compiled Gea apps and map Gea primitives onto native
platform controls where possible. This repo is the Apple platform adapter
layer. It owns native shells, generated SDK binding surfaces, and
Apple-specific target build scripts.

## License

Apache-2.0 (see `LICENSE`). You can ship closed-source products
built on it. The only GeaStack code under a different license is
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

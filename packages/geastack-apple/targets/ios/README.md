# iOS target

Build a Gea JSX app as a native UIKit app.

The app needs `@geastack/apple` and `@geastack/cli` (0.1.110 or later for tvOS)
in its own dependencies and `"ios": true` under `gea.targets` in its
`package.json`; `npx create-geastack my-app --targets ios` sets up all three,
and for an existing app:

```bash
npm install @geastack/apple
npm install --save-dev @geastack/cli
```

From the app folder, the CLI drives this target:

```bash
npx gea build --target ios                 # simulator .app, no launch
npx gea build --target ios --mode device   # unsigned iphoneos .app
npx gea run --target ios                   # build, install and launch on a simulator
npx gea run --target ios --mode device     # build, sign, install and launch on an iPhone
```

The CLI runs `build-ios.sh <app-id> <simulator|device> [tvos]` from the
installed package, with `GEA_IOS_SKIP_LAUNCH=1` for `gea build` and the app's
build configuration from `gea.targets.ios`. The script can also be run
directly from the app folder; it then installs and launches the app after
building unless `GEA_IOS_SKIP_LAUNCH=1` is set, and does not apply the
`gea.targets.ios.build` settings:

```bash
GEA_IOS_SKIP_LAUNCH=1 node_modules/@geastack/apple/targets/ios/build-ios.sh <app-id> simulator
```

The script resolves `@geastack/core`, `@geastack/compiler`, the apple-native
geatsc plugin and `@geastack/cli` by walking up `node_modules` from the app
folder, so it works on a hoisted npm install and on a linked checkout alike.

The simulator path auto-picks an available iPhone simulator. Set
`GEA_IOS_SIMULATOR_UDID` to force a specific device. By default, the script
also opens Simulator.app for the selected device; set
`GEA_IOS_OPEN_SIMULATOR=0` to leave the simulator GUI alone.

For an attached iPhone, the script uses Xcode's last selected development
team when it can find one. You can also set your Apple development team
explicitly:

```bash
GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 npx gea run --target ios --mode device
```

To see the automatically detected team id:

```bash
node node_modules/@geastack/apple/targets/ios/detect-development-team.mjs
```

Signed device builds auto-pick an attached iPhone with Developer Mode enabled,
install the app with `devicectl`, and launch it in the foreground. Set
`GEA_IOS_DEVICE_ID` to force a specific device. Signed device builds allow
Xcode to create or update provisioning profiles by default. Disable that with
`GEA_IOS_ALLOW_PROVISIONING_UPDATES=0`.

To only verify that the app compiles for the iPhone device SDK, skip launch
without a development team:

```bash
npx gea build --target ios --mode device
```

The Xcode project is generated under
`<app>/dist/ios/<app-id>/GeaIos.xcodeproj`. Open it after running the script
if you want to inspect signing or launch through Xcode. Do not hand-edit it as
the source of truth.

## tvOS

Apps that declare `gea.targets.tvos` can use the shared UIKit host on tvOS 17
or later. Install the tvOS platform in Xcode's Components settings. The app
needs the same `@geastack/apple` and `@geastack/cli` dependencies as on iOS
(the `three-tvos` example lists both). From the app folder, run it on an Apple
TV simulator:

```sh
npx gea run --target tvos
```

For a physical Apple TV, pair it with Xcode over the local network and use an
Apple development team configured for the device:

```sh
GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 npx gea run --target tvos --mode device
```

Use `gea build` with the same options to generate the Xcode project and build
without launching. Outputs are under the app's `dist/tvos`. The UIKit build
script shares its signing, device selection, and simulator overrides with iOS.

An app can pin the resolution it renders at, for example 4K on Apple TV, with
`gea.targets.tvos.build.display` (`gea.targets.ios.build.display` on iOS):

```json
"tvos": { "build": { "display": { "width": 3840, "height": 2160 } } }
```

Set both or neither. Per-target native code goes under `gea.targets.<ios|tvos>`:
`nativeSources`, `nativeLibraries` (static archives), `frameworks` (system
frameworks), `nativeIncludeDirectories`, `nativeResources` (directories copied
into the bundle) and `tsconfig` (the TypeScript project the compiler reads).
Native code can own part of the window as a host extension, a rendering
surface for example, by registering itself through `main/gea_uikit_host.h`.

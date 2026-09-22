# iOS target

Build a gea-embedded JSX app as a native UIKit app.

From an app that depends on `@geastack/apple` (every iOS example does, and
`gea create --targets ios` adds it), the CLI drives this target:

```bash
npx gea build --target ios                 # simulator .app, no launch
npx gea build --target ios --mode device   # unsigned iphoneos .app
npx gea run --target ios                   # build, install and launch on a simulator
npx gea run --target ios --mode device     # build, sign, install and launch on an iPhone
```

The same script can be run directly from the app folder; the CLI passes the
app id and destination through unchanged:

```bash
node_modules/@geastack/apple/targets/ios/build-ios.sh <app-id> simulator
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
targets/ios/detect-development-team.mjs
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

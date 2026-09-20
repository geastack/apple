# @geastack/apple

Apple platform support for GeaStack: generated TypeScript bindings for the
Apple SDKs, and the macOS and iOS native build targets that turn a compiled Gea
app into an `.app`.

```sh
npm install @geastack/apple
```

## Building an app

The `gea` CLI drives the targets:

```sh
gea build --target macos
gea build --target ios
```

The target build scripts can also be run directly from an app directory that
has the GeaStack packages installed:

```sh
node_modules/@geastack/apple/targets/macos/build-macos.sh my-app
node_modules/@geastack/apple/targets/ios/build-ios.sh my-app simulator
GEA_IOS_DEVELOPMENT_TEAM=ABCDE12345 node_modules/@geastack/apple/targets/ios/build-ios.sh my-app device
```

Requires Xcode with the macOS and iOS SDKs. Each target directory has its own
README covering the renderer and project layout.

## Using Apple frameworks from TypeScript

Bindings are exported per framework, for example `@geastack/apple/UIKit`,
`@geastack/apple/AppKit`, `@geastack/apple/Metal`, `@geastack/apple/MapKit`
and `@geastack/apple/Foundation`:

```ts
import { UIView, UILabel } from '@geastack/apple/UIKit'
```

Calls into these bindings are compiled to native Objective-C++ by `geatsc`
through `@geastack/geatsc-plugin-apple-native`, which reads binding metadata
the build generates from this package's declarations.

## App Store

The package is Apache-2.0, so App Store distribution has no license obstacle
from this package. See the repository README for the position on the
GPL-licensed embedded packages.

## License

Apache-2.0. See `LICENSE`.

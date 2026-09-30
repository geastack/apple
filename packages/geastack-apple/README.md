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

## Desktop services

`@geastack/apple/AppKit` exports `NSStatusBar`, `NSStatusItem`, `NSStatusBarButton`,
`NSMenu`, and `NSMenuItem`. Obtain the shared bar with
`NSStatusBar.systemStatusBar()`, create an item with `statusItemWithLength(-1)`
(variable width), set its button title or menu, and retain the item while it is
in use. Menu items use the existing `ObjCTarget`/selector action bridge.
Remove the item with `removeStatusItem(item)` when finished.

```ts
import { randomUUID, localTimeZone, readTextFile, writeTextFile,
  watchPath, stopWatchingPath, sharedContainerPath } from '@geastack/apple/Foundation'

const id = randomUUID()
const timeZone = localTimeZone() // IANA time-zone name
const folder = sharedContainerPath('group.example.app')
writeTextFile(folder + '/snapshot.json', JSON.stringify({ id, timeZone }))
const watch = watchPath(folder, () => {
  const snapshot = readTextFile(folder + '/snapshot.json')
  // Reload application state from the snapshot.
})
// Call when the owner is disposed:
stopWatchingPath(watch)
```

File reads and atomic UTF-8 writes are synchronous. Errors throw. Path observation delivers callbacks on the main queue. Observe a file for
in-place writes, or its directory for entry changes and atomic file replacements.
Observation is not recursive; after replacing a file, recreate its file observer
or keep observing its directory. Stop observing before releasing callback-owned state. Sandbox file access
still requires the application's usual entitlements or granted access.
`sharedContainerPath` requires matching App Group entitlements on the app and its
WidgetKit extension. It exposes shared storage; the extension remains a separate
Xcode target.

`@geastack/apple/Security` exports `writePassword(service, account, password)`,
`readPassword(service, account)`, and `deletePassword(service, account)`. Write
and delete return the native `OSStatus` (zero means success); read throws on a
failed lookup. They use generic-password Keychain items.

`@geastack/apple/UserNotifications` exports `requestAuthorization(callback)`,
`scheduleNotification(id, title, body, delaySeconds, callback)`, and
`cancelNotification(id)`. Authorization returns `(granted, error)`; scheduling
returns an error string (empty on success). Delays must be positive and finite.
Completion callbacks run on the main queue. Request authorization from the
signed application before scheduling; the operating system controls delivery.

## App Store

The package is Apache-2.0, so App Store distribution has no license obstacle
from this package. See the repository README for the position on the
GPL-licensed embedded packages.

## License

Apache-2.0. See `LICENSE`.

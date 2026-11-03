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

`@geastack/apple/EventKit` reads and writes the calendars the user has added to
macOS (iCloud, Google, Exchange and other accounts in System Settings → Internet
Accounts) through one shared `EKEventStore` for the process. Results are JSON
strings, like `SwiftData.fetchModelsJSON`; parse them with `JSON.parse`.

- `authorizationStatus()` returns `notDetermined`, `restricted`, `denied`,
  `fullAccess` or `writeOnly`.
- `requestFullAccess((granted, error) => …)` shows the system prompt once
  (`requestFullAccessToEventsWithCompletion:` on macOS 14 and later, the older
  event access request below).
- `calendars()` returns
  `[{ id, title, color, source, sourceType, allowsModifications }]`. `id` is the
  calendar identifier, `source` the account title (the address for a Google
  account), `color` is `#RRGGBB`, and `sourceType` is one of `local`,
  `exchange`, `calDAV` (Google and most other servers), `mobileMe`,
  `subscribed` or `birthdays`. It is `[]` until access is granted.
- `events(startISO, endISO, calendarIdsJSON)` returns the events overlapping
  the range, sorted by start:
  `[{ id, externalId, calendarId, title, start, end, occurrenceDate, allDay,
  availability, recurring, status }]`. Pass `'[]'` for all calendars. Times are
  ISO 8601 with the local offset; input accepts any offset, with or without
  fractional seconds. `availability` is `busy`, `free`, `tentative`,
  `unavailable` or `notSupported`; `status` is `none`, `confirmed`, `tentative`
  or `canceled`. Occurrences of a recurring event share `id`; `id` plus
  `occurrenceDate` names one occurrence. EventKit limits a query to four years.
- `watchChanges(() => …)` returns a handle; the callback runs on the main queue
  after any change to the store (from this app, Calendar or a sync). Re-read
  what you show; the notification carries no details. Stop it with
  `stopWatchingChanges(handle)`.
- `saveEvent(eventJSON, span, (id, error) => …)` creates an event when
  `eventJSON` has no `id`, and otherwise updates the event (with
  `occurrenceDate`, that occurrence; without it, the first occurrence). Fields:
  `calendarId`, `title`, `start`, `end`, `allDay`, `location`, `notes`,
  `availability`; a new event needs `calendarId`, `start` and `end`, and an
  update changes only the fields given. `span` is `thisEvent` or
  `futureEvents`.
- `removeEvent(id, occurrenceDate, span, error => …)` removes an event or
  occurrence (`occurrenceDate` may be `''` for a single event).

Writes to a calendar whose `allowsModifications` is false return an error.
EventKit cannot add attendees or send invitations; an event saved here has no
invitees. Completion callbacks run on the main queue; errors are an empty
string on success. A located occurrence must lie within a week of its
`occurrenceDate`.

macOS ends a process that asks for calendar access without a usage
description. Add both keys to `apps/<id>/macos.json`; its optional `infoPlist`
object is merged over the shared `Info.plist` template:

```json
{
  "window": { "width": 1280, "height": 800 },
  "infoPlist": {
    "NSCalendarsFullAccessUsageDescription": "Shows your meetings next to your tasks.",
    "NSCalendarsUsageDescription": "Shows your meetings next to your tasks."
  }
}
```

macOS records the grant against the code signature. A development build is
signed ad hoc, so every rebuild that changes the executable asks again, and
`tccutil reset Calendar com.gea.<app-id>` forgets it. A sandboxed or
hardened-runtime signed build also needs the
`com.apple.security.personal-information.calendars` entitlement. A Google
account in macOS syncs only its own calendars by default; switch on shared and
secondary calendars once at https://www.google.com/calendar/syncselect.

```ts
import { authorizationStatus, requestFullAccess, calendars, events, watchChanges } from '@geastack/apple/EventKit'

const load = () => {
  const accounts = JSON.parse(calendars())
  const week = JSON.parse(events('2026-11-02T00:00:00+01:00', '2026-11-09T00:00:00+01:00', '[]'))
  // Group accounts by `source`, render `week`.
}
if (authorizationStatus() === 'fullAccess') load()
else requestFullAccess((granted) => { if (granted) load() })
const watch = watchChanges(load)
```

## App Store

The package is Apache-2.0, so App Store distribution has no license obstacle
from this package. See the repository README for the position on the
GPL-licensed embedded packages.

## License

Apache-2.0. See `LICENSE`.

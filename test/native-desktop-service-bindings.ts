//! compile-only
//! emitted-has: gea::apple::Foundation::randomUUID
//! emitted-has: gea::apple::Security::writePassword
//! emitted-has: gea::apple::UserNotifications::scheduleNotification
//! emitted-has: gea::apple::EventKit::events
//! emitted-has: gea::apple::EventKit::saveEvent
import '@geastack/core'
import {
  randomUUID,
  localTimeZone,
  readTextFile,
  writeTextFile,
  watchPath,
  stopWatchingPath,
  sharedContainerPath
} from '@geastack/apple/Foundation'
import { writePassword, readPassword, deletePassword } from '@geastack/apple/Security'
import { requestAuthorization, scheduleNotification, cancelNotification } from '@geastack/apple/UserNotifications'
import {
  authorizationStatus,
  requestFullAccess,
  calendars,
  events,
  watchChanges,
  stopWatchingChanges,
  saveEvent,
  removeEvent
} from '@geastack/apple/EventKit'
import { NSStatusBar, NSMenu, NSMenuItem } from '@geastack/apple/AppKit'
const id = randomUUID()
const zone = localTimeZone()
const folder = sharedContainerPath('group.example.test')
writeTextFile(folder + '/snapshot.json', JSON.stringify({ id, zone }))
const observer = watchPath(folder, () => {
  console.log(readTextFile(folder + '/snapshot.json'))
})
stopWatchingPath(observer)
console.log('' + writePassword('example', 'account', id) + readPassword('example', 'account') + deletePassword('example', 'account'))
requestAuthorization((granted, error) => {
  console.log('' + granted + error)
})
scheduleNotification(id, 'Title', 'Body', 60, (error) => {
  console.log(error)
})
cancelNotification(id)
const bar = NSStatusBar.systemStatusBar()
const item = bar.statusItemWithLength(-1)
const menu = new NSMenu()
const entry = new NSMenuItem()
entry.title = 'Open'
menu.addItem(entry)
item.menu = menu
bar.removeStatusItem(item)
if (authorizationStatus() !== 'fullAccess') {
  requestFullAccess((granted, error) => {
    console.log('' + granted + error)
  })
}
const calendarList = JSON.parse(calendars()) as Array<{ id: string; allowsModifications: boolean }>
const week = JSON.parse(events('2026-11-02T00:00:00Z', '2026-11-09T00:00:00Z', JSON.stringify([]))) as Array<{ id: string; occurrenceDate: string }>
const calendarWatch = watchChanges(() => {
  console.log(calendars())
})
stopWatchingChanges(calendarWatch)
saveEvent(JSON.stringify({ calendarId: calendarList[0].id, title: 'Block', start: '2026-11-03T09:00:00Z', end: '2026-11-03T10:00:00Z' }), 'thisEvent', (saved, error) => {
  console.log(saved + error)
})
removeEvent(week[0].id, week[0].occurrenceDate, 'thisEvent', (error) => {
  console.log(error)
})

//! compile-only
//! emitted-has: gea::apple::Foundation::randomUUID
//! emitted-has: gea::apple::Security::writePassword
//! emitted-has: gea::apple::UserNotifications::scheduleNotification
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

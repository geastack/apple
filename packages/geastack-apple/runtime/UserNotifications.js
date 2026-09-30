function geaAppleUserNotificationsNativeOnly(name) {
  throw new Error(`@geastack/apple/UserNotifications ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function requestAuthorization() {
  return geaAppleUserNotificationsNativeOnly("requestAuthorization")
}

export function scheduleNotification() {
  return geaAppleUserNotificationsNativeOnly("scheduleNotification")
}

export function cancelNotification() {
  return geaAppleUserNotificationsNativeOnly("cancelNotification")
}

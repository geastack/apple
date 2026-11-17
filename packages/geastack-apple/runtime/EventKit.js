function geaAppleEventKitNativeOnly(name) {
  throw new Error(`@geastack/apple/EventKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function authorizationStatus() {
  return geaAppleEventKitNativeOnly("authorizationStatus")
}

export function requestFullAccess() {
  return geaAppleEventKitNativeOnly("requestFullAccess")
}

export function calendars() {
  return geaAppleEventKitNativeOnly("calendars")
}

export function events() {
  return geaAppleEventKitNativeOnly("events")
}

export function watchChanges() {
  return geaAppleEventKitNativeOnly("watchChanges")
}

export function stopWatchingChanges() {
  return geaAppleEventKitNativeOnly("stopWatchingChanges")
}

export function saveEvent() {
  return geaAppleEventKitNativeOnly("saveEvent")
}

export function removeEvent() {
  return geaAppleEventKitNativeOnly("removeEvent")
}

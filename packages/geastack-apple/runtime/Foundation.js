function geaAppleFoundationNativeOnly(name) {
  throw new Error(`@geastack/apple/Foundation ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function randomUUID() {
  return geaAppleFoundationNativeOnly("randomUUID")
}

export function localTimeZone() {
  return geaAppleFoundationNativeOnly("localTimeZone")
}

export function sharedContainerPath() {
  return geaAppleFoundationNativeOnly("sharedContainerPath")
}

export function readTextFile() {
  return geaAppleFoundationNativeOnly("readTextFile")
}

export function writeTextFile() {
  return geaAppleFoundationNativeOnly("writeTextFile")
}

export function watchPath() {
  return geaAppleFoundationNativeOnly("watchPath")
}

export function stopWatchingPath() {
  return geaAppleFoundationNativeOnly("stopWatchingPath")
}

export class NSObject {
}

export class NSData {
}

export class NSDictionary {
  static dictionary() {
    return geaAppleFoundationNativeOnly("NSDictionary.dictionary")
  }
}

export class NSURL {
  static URLWithString() {
    return geaAppleFoundationNativeOnly("NSURL.URLWithString")
  }
}

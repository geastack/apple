function geaAppleActivityKitNativeOnly(name) {
  throw new Error(`@geajs/apple/ActivityKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function requestLiveActivity() {
  return geaAppleActivityKitNativeOnly("requestLiveActivity")
}

export function updateLiveActivity() {
  return geaAppleActivityKitNativeOnly("updateLiveActivity")
}

export function endLiveActivity() {
  return geaAppleActivityKitNativeOnly("endLiveActivity")
}

export class LiveActivityHandle {
}

function geaAppleCoreMediaNativeOnly(name) {
  throw new Error(`@geajs/apple/CoreMedia ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function CMTimeMakeWithSeconds() {
  return geaAppleCoreMediaNativeOnly("CMTimeMakeWithSeconds")
}

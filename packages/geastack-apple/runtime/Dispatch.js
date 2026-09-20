function geaAppleDispatchNativeOnly(name) {
  throw new Error(`@geajs/apple/Dispatch ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function dispatchAsyncGlobal() {
  return geaAppleDispatchNativeOnly("dispatchAsyncGlobal")
}

export function dispatchAsyncMain() {
  return geaAppleDispatchNativeOnly("dispatchAsyncMain")
}

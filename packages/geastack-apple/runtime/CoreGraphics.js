function geaAppleCoreGraphicsNativeOnly(name) {
  throw new Error(`@geajs/apple/CoreGraphics ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function CGRectMake() {
  return geaAppleCoreGraphicsNativeOnly("CGRectMake")
}

export function CGPointMake() {
  return geaAppleCoreGraphicsNativeOnly("CGPointMake")
}

export function CGSizeMake() {
  return geaAppleCoreGraphicsNativeOnly("CGSizeMake")
}

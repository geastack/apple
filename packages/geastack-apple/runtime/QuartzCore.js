function geaAppleQuartzCoreNativeOnly(name) {
  throw new Error(`@geajs/apple/QuartzCore ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export class CALayer {
  addSublayer() {
    return geaAppleQuartzCoreNativeOnly("CALayer.addSublayer")
  }
}

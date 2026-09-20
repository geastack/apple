function geaAppleMetalKitNativeOnly(name) {
  throw new Error(`@geajs/apple/MetalKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export class MTKView {
  constructor() {
    geaAppleMetalKitNativeOnly("new MTKView")
  }
}

export class MTKViewDelegate {
  static create() {
    return geaAppleMetalKitNativeOnly("MTKViewDelegate.create")
  }
}

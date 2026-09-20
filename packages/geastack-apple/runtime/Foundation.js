function geaAppleFoundationNativeOnly(name) {
  throw new Error(`@geajs/apple/Foundation ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
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

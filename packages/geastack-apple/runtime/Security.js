function geaAppleSecurityNativeOnly(name) {
  throw new Error(`@geastack/apple/Security ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function writePassword() {
  return geaAppleSecurityNativeOnly("writePassword")
}

export function readPassword() {
  return geaAppleSecurityNativeOnly("readPassword")
}

export function deletePassword() {
  return geaAppleSecurityNativeOnly("deletePassword")
}

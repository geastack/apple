function geaApplePhotosNativeOnly(name) {
  throw new Error(`@geajs/apple/Photos ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export class PHPhotoLibrary {
  static saveImageData() {
    return geaApplePhotosNativeOnly("PHPhotoLibrary.saveImageData")
  }
}

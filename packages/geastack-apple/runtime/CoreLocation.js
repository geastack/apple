function geaAppleCoreLocationNativeOnly(name) {
  throw new Error(`@geajs/apple/CoreLocation ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const kCLLocationAccuracyBest = -1
export const CLDistanceFilterNone = -1
export const CLAuthorizationStatusNotDetermined = 0
export const CLAuthorizationStatusAuthorizedWhenInUse = 4

export function CLLocationCoordinate2DMake() {
  return geaAppleCoreLocationNativeOnly("CLLocationCoordinate2DMake")
}

export class CLLocation {
}

export class CLLocationManager {
  constructor() {
    geaAppleCoreLocationNativeOnly("new CLLocationManager")
  }
  requestWhenInUseAuthorization() {
    return geaAppleCoreLocationNativeOnly("CLLocationManager.requestWhenInUseAuthorization")
  }
  startUpdatingLocation() {
    return geaAppleCoreLocationNativeOnly("CLLocationManager.startUpdatingLocation")
  }
  stopUpdatingLocation() {
    return geaAppleCoreLocationNativeOnly("CLLocationManager.stopUpdatingLocation")
  }
}

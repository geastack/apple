function geaAppleMapKitNativeOnly(name) {
  throw new Error(`@geajs/apple/MapKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const MKMapTypeStandard = 0
export const MKMapTypeMutedStandard = 1
export const MKMapTypeSatellite = 2
export const MKUserTrackingModeNone = 0
export const MKUserTrackingModeFollow = 1

export function MKCoordinateRegionMakeWithDistance() {
  return geaAppleMapKitNativeOnly("MKCoordinateRegionMakeWithDistance")
}

export class MKMapView {
  constructor() {
    geaAppleMapKitNativeOnly("new MKMapView")
  }
  setRegionAnimated() {
    return geaAppleMapKitNativeOnly("MKMapView.setRegionAnimated")
  }
}

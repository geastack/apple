import type { CLLocationCoordinate2D } from '@geastack/apple/CoreLocation'
import type { UIView } from '@geastack/apple/UIKit'

export declare const MKMapTypeStandard: number
export declare const MKMapTypeMutedStandard: number
export declare const MKMapTypeSatellite: number
export declare const MKUserTrackingModeNone: number
export declare const MKUserTrackingModeFollow: number

export declare function MKCoordinateRegionMakeWithDistance(centerCoordinate: CLLocationCoordinate2D, latitudinalMeters: number, longitudinalMeters: number): MKCoordinateRegion

export interface MKCoordinateSpan {
  latitudeDelta: number
  longitudeDelta: number
}

export interface MKCoordinateRegion {
  center: CLLocationCoordinate2D
  span: MKCoordinateSpan
}

export declare class MKMapView extends UIView {
  constructor()
  mapType: number
  showsUserLocation: boolean
  userTrackingMode: number
  setRegionAnimated(region: MKCoordinateRegion, animated: boolean): void
}

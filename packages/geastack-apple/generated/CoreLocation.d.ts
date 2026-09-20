import type { NSObject } from '@geastack/apple/Foundation'

export declare const kCLLocationAccuracyBest: number
export declare const CLDistanceFilterNone: number
export declare const CLAuthorizationStatusNotDetermined: number
export declare const CLAuthorizationStatusAuthorizedWhenInUse: number

export declare function CLLocationCoordinate2DMake(latitude: number, longitude: number): CLLocationCoordinate2D

export interface CLLocationCoordinate2D {
  latitude: number
  longitude: number
}

export declare class CLLocation extends NSObject {
  readonly coordinate: CLLocationCoordinate2D
  readonly horizontalAccuracy: number
}

export declare class CLLocationManager extends NSObject {
  constructor()
  desiredAccuracy: number
  distanceFilter: number
  readonly location: CLLocation | null
  requestWhenInUseAuthorization(): void
  startUpdatingLocation(): void
  stopUpdatingLocation(): void
}

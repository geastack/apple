import type { CGRect, CGPoint } from '@geastack/apple/CoreGraphics'
import type { CMTime } from '@geastack/apple/CoreMedia'
import type { NSData, NSObject } from '@geastack/apple/Foundation'
import type { CALayer } from '@geastack/apple/QuartzCore'

export declare const AVMediaTypeVideo: string
export declare const AVLayerVideoGravityResizeAspectFill: string
export declare const AVCaptureSessionPresetPhoto: string
export declare const AVCaptureSessionPresetHigh: string
export declare const AVCaptureSessionPresetMedium: string
export declare const AVCaptureFocusModeLocked: number
export declare const AVCaptureFocusModeAutoFocus: number
export declare const AVCaptureFocusModeContinuousAutoFocus: number
export declare const AVCaptureExposureModeLocked: number
export declare const AVCaptureExposureModeAutoExpose: number
export declare const AVCaptureExposureModeContinuousAutoExposure: number
export declare const AVCaptureExposureModeCustom: number
export declare const AVCaptureWhiteBalanceModeLocked: number
export declare const AVCaptureWhiteBalanceModeAutoWhiteBalance: number
export declare const AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance: number
export declare const AVCaptureFlashModeOff: number
export declare const AVCaptureFlashModeOn: number
export declare const AVCaptureFlashModeAuto: number
export declare const AVCapturePhotoQualityPrioritizationSpeed: number
export declare const AVCapturePhotoQualityPrioritizationBalanced: number
export declare const AVCapturePhotoQualityPrioritizationQuality: number
export declare const AVCaptureDevicePositionUnspecified: number
export declare const AVCaptureDevicePositionBack: number
export declare const AVCaptureDevicePositionFront: number
export declare const AVCaptureDeviceTypeBuiltInWideAngleCamera: string
export declare const AVCaptureDeviceTypeBuiltInUltraWideCamera: string
export declare const AVCaptureDeviceTypeBuiltInTelephotoCamera: string
export declare const AVCaptureDeviceTypeBuiltInDualCamera: string
export declare const AVCaptureDeviceTypeBuiltInDualWideCamera: string
export declare const AVCaptureDeviceTypeBuiltInTripleCamera: string

export declare class AVCaptureInput extends NSObject {
}

export declare class AVCaptureOutput extends NSObject {
}

export declare class AVCaptureDeviceFormat extends NSObject {
  readonly minISO: number
  readonly maxISO: number
  readonly videoMaxZoomFactor: number
}

export declare class AVCaptureDevice extends NSObject {
  readonly activeFormat: AVCaptureDeviceFormat
  videoZoomFactor: number
  readonly minAvailableVideoZoomFactor: number
  readonly maxAvailableVideoZoomFactor: number
  focusPointOfInterest: CGPoint
  focusMode: number
  readonly isFocusPointOfInterestSupported: boolean
  exposurePointOfInterest: CGPoint
  exposureMode: number
  readonly isExposurePointOfInterestSupported: boolean
  readonly exposureTargetBias: number
  readonly minExposureTargetBias: number
  readonly maxExposureTargetBias: number
  readonly ISO: number
  whiteBalanceMode: number
  readonly hasFlash: boolean
  readonly virtualDeviceSwitchOverVideoZoomFactors: number[]
  static defaultDeviceWithMediaType(mediaType: string): AVCaptureDevice | null
  static defaultDeviceWithDeviceTypeMediaTypePosition(deviceType: string, mediaType: string, position: number): AVCaptureDevice | null
  lockForConfiguration(): boolean
  unlockForConfiguration(): void
  isFocusModeSupported(focusMode: number): boolean
  isExposureModeSupported(exposureMode: number): boolean
  isWhiteBalanceModeSupported(whiteBalanceMode: number): boolean
  isFlashModeSupported(flashMode: number): boolean
  setExposureTargetBiasCompletionHandler(bias: number, handler: (syncTime: CMTime) => void): void
  setExposureModeCustomWithDurationISOCompletionHandler(duration: CMTime, ISO: number, handler: (syncTime: CMTime) => void): void
}

export declare class AVCaptureDeviceInput extends AVCaptureInput {
  static deviceInputWithDevice(device: AVCaptureDevice): AVCaptureDeviceInput | null
}

export declare class AVCaptureSession extends NSObject {
  constructor()
  sessionPreset: string
  beginConfiguration(): void
  commitConfiguration(): void
  canAddInput(input: AVCaptureInput): boolean
  canSetSessionPreset(preset: string): boolean
  addInput(input: AVCaptureInput): void
  canAddOutput(output: AVCaptureOutput): boolean
  addOutput(output: AVCaptureOutput): void
  startRunning(): void
  stopRunning(): void
}

export declare class AVCapturePhotoSettings extends NSObject {
  flashMode: number
  photoQualityPrioritization: number
  static photoSettings(): AVCapturePhotoSettings
}

export declare class AVCapturePhotoOutput extends AVCaptureOutput {
  constructor()
  maxPhotoQualityPrioritization: number
  capturePhotoWithSettingsHandler(settings: AVCapturePhotoSettings, handler: (data: NSData, error: string) => void): void
}

export declare class AVCaptureVideoPreviewLayer extends CALayer {
  videoGravity: string
  static layerWithSession(session: AVCaptureSession): AVCaptureVideoPreviewLayer
}

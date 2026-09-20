function geaAppleAVFoundationNativeOnly(name) {
  throw new Error(`@geajs/apple/AVFoundation ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const AVMediaTypeVideo = "vide"
export const AVLayerVideoGravityResizeAspectFill = "resizeAspectFill"
export const AVCaptureSessionPresetPhoto = "Photo"
export const AVCaptureSessionPresetHigh = "High"
export const AVCaptureSessionPresetMedium = "Medium"
export const AVCaptureFocusModeLocked = 0
export const AVCaptureFocusModeAutoFocus = 1
export const AVCaptureFocusModeContinuousAutoFocus = 2
export const AVCaptureExposureModeLocked = 0
export const AVCaptureExposureModeAutoExpose = 1
export const AVCaptureExposureModeContinuousAutoExposure = 2
export const AVCaptureExposureModeCustom = 3
export const AVCaptureWhiteBalanceModeLocked = 0
export const AVCaptureWhiteBalanceModeAutoWhiteBalance = 1
export const AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance = 2
export const AVCaptureFlashModeOff = 0
export const AVCaptureFlashModeOn = 1
export const AVCaptureFlashModeAuto = 2
export const AVCapturePhotoQualityPrioritizationSpeed = 1
export const AVCapturePhotoQualityPrioritizationBalanced = 2
export const AVCapturePhotoQualityPrioritizationQuality = 3
export const AVCaptureDevicePositionUnspecified = 0
export const AVCaptureDevicePositionBack = 1
export const AVCaptureDevicePositionFront = 2
export const AVCaptureDeviceTypeBuiltInWideAngleCamera = "AVCaptureDeviceTypeBuiltInWideAngleCamera"
export const AVCaptureDeviceTypeBuiltInUltraWideCamera = "AVCaptureDeviceTypeBuiltInUltraWideCamera"
export const AVCaptureDeviceTypeBuiltInTelephotoCamera = "AVCaptureDeviceTypeBuiltInTelephotoCamera"
export const AVCaptureDeviceTypeBuiltInDualCamera = "AVCaptureDeviceTypeBuiltInDualCamera"
export const AVCaptureDeviceTypeBuiltInDualWideCamera = "AVCaptureDeviceTypeBuiltInDualWideCamera"
export const AVCaptureDeviceTypeBuiltInTripleCamera = "AVCaptureDeviceTypeBuiltInTripleCamera"

export class AVCaptureInput {
}

export class AVCaptureOutput {
}

export class AVCaptureDeviceFormat {
}

export class AVCaptureDevice {
  static defaultDeviceWithMediaType() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.defaultDeviceWithMediaType")
  }
  static defaultDeviceWithDeviceTypeMediaTypePosition() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.defaultDeviceWithDeviceTypeMediaTypePosition")
  }
  lockForConfiguration() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.lockForConfiguration")
  }
  unlockForConfiguration() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.unlockForConfiguration")
  }
  isFocusModeSupported() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.isFocusModeSupported")
  }
  isExposureModeSupported() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.isExposureModeSupported")
  }
  isWhiteBalanceModeSupported() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.isWhiteBalanceModeSupported")
  }
  isFlashModeSupported() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.isFlashModeSupported")
  }
  setExposureTargetBiasCompletionHandler() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.setExposureTargetBiasCompletionHandler")
  }
  setExposureModeCustomWithDurationISOCompletionHandler() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDevice.setExposureModeCustomWithDurationISOCompletionHandler")
  }
}

export class AVCaptureDeviceInput {
  static deviceInputWithDevice() {
    return geaAppleAVFoundationNativeOnly("AVCaptureDeviceInput.deviceInputWithDevice")
  }
}

export class AVCaptureSession {
  constructor() {
    geaAppleAVFoundationNativeOnly("new AVCaptureSession")
  }
  beginConfiguration() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.beginConfiguration")
  }
  commitConfiguration() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.commitConfiguration")
  }
  canAddInput() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.canAddInput")
  }
  canSetSessionPreset() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.canSetSessionPreset")
  }
  addInput() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.addInput")
  }
  canAddOutput() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.canAddOutput")
  }
  addOutput() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.addOutput")
  }
  startRunning() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.startRunning")
  }
  stopRunning() {
    return geaAppleAVFoundationNativeOnly("AVCaptureSession.stopRunning")
  }
}

export class AVCapturePhotoSettings {
  static photoSettings() {
    return geaAppleAVFoundationNativeOnly("AVCapturePhotoSettings.photoSettings")
  }
}

export class AVCapturePhotoOutput {
  constructor() {
    geaAppleAVFoundationNativeOnly("new AVCapturePhotoOutput")
  }
  capturePhotoWithSettingsHandler() {
    return geaAppleAVFoundationNativeOnly("AVCapturePhotoOutput.capturePhotoWithSettingsHandler")
  }
}

export class AVCaptureVideoPreviewLayer {
  static layerWithSession() {
    return geaAppleAVFoundationNativeOnly("AVCaptureVideoPreviewLayer.layerWithSession")
  }
}

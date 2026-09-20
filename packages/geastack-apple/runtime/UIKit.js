function geaAppleUIKitNativeOnly(name) {
  throw new Error(`@geajs/apple/UIKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const UIAlertActionStyleDefault = 0
export const UIAlertActionStyleCancel = 1
export const UIAlertActionStyleDestructive = 2
export const UIAlertControllerStyleActionSheet = 0
export const UIAlertControllerStyleAlert = 1
export const UIModalPresentationFullScreen = 0
export const UIControlEventTouchDown = 1
export const UIControlEventTouchUpInside = 64
export const UIControlEventTouchUpOutside = 128
export const UIControlEventTouchCancel = 256
export const UIControlEventValueChanged = 4096
export const ObjCTargetAction = "invoke:"

export function installRootView() {
  return geaAppleUIKitNativeOnly("installRootView")
}

export class UIColor {
  static systemBackgroundColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemBackgroundColor")
  }
  static systemGroupedBackgroundColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemGroupedBackgroundColor")
  }
  static secondarySystemGroupedBackgroundColor() {
    return geaAppleUIKitNativeOnly("UIColor.secondarySystemGroupedBackgroundColor")
  }
  static labelColor() {
    return geaAppleUIKitNativeOnly("UIColor.labelColor")
  }
  static secondaryLabelColor() {
    return geaAppleUIKitNativeOnly("UIColor.secondaryLabelColor")
  }
  static systemBlueColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemBlueColor")
  }
  static systemIndigoColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemIndigoColor")
  }
  static systemPurpleColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemPurpleColor")
  }
  static systemTealColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemTealColor")
  }
  static systemGreenColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemGreenColor")
  }
  static systemOrangeColor() {
    return geaAppleUIKitNativeOnly("UIColor.systemOrangeColor")
  }
  static systemGray5Color() {
    return geaAppleUIKitNativeOnly("UIColor.systemGray5Color")
  }
  static whiteColor() {
    return geaAppleUIKitNativeOnly("UIColor.whiteColor")
  }
  static blackColor() {
    return geaAppleUIKitNativeOnly("UIColor.blackColor")
  }
  static colorWithRed() {
    return geaAppleUIKitNativeOnly("UIColor.colorWithRed")
  }
  static colorWithRedGreenBlueAlpha() {
    return geaAppleUIKitNativeOnly("UIColor.colorWithRedGreenBlueAlpha")
  }
}

export class UIFont {
  static systemFontOfSize() {
    return geaAppleUIKitNativeOnly("UIFont.systemFontOfSize")
  }
  static systemFontOfSizeWeight() {
    return geaAppleUIKitNativeOnly("UIFont.systemFontOfSizeWeight")
  }
  static boldSystemFontOfSize() {
    return geaAppleUIKitNativeOnly("UIFont.boldSystemFontOfSize")
  }
}

export class UIScreen {
  static mainScreen() {
    return geaAppleUIKitNativeOnly("UIScreen.mainScreen")
  }
}

export class UIApplication {
  static sharedApplication() {
    return geaAppleUIKitNativeOnly("UIApplication.sharedApplication")
  }
  openURL() {
    return geaAppleUIKitNativeOnly("UIApplication.openURL")
  }
  openURLOptionsCompletionHandler() {
    return geaAppleUIKitNativeOnly("UIApplication.openURLOptionsCompletionHandler")
  }
}

export class UIViewController {
  constructor() {
    geaAppleUIKitNativeOnly("new UIViewController")
  }
  presentViewControllerAnimatedCompletion() {
    return geaAppleUIKitNativeOnly("UIViewController.presentViewControllerAnimatedCompletion")
  }
  dismissViewControllerAnimatedCompletion() {
    return geaAppleUIKitNativeOnly("UIViewController.dismissViewControllerAnimatedCompletion")
  }
}

export class UINavigationController {
  constructor(rootViewController) {
    geaAppleUIKitNativeOnly("new UINavigationController")
  }
}

export class UIAlertAction {
  static actionWithTitleStyleHandler() {
    return geaAppleUIKitNativeOnly("UIAlertAction.actionWithTitleStyleHandler")
  }
}

export class UIAlertController {
  static alertControllerWithTitleMessagePreferredStyle() {
    return geaAppleUIKitNativeOnly("UIAlertController.alertControllerWithTitleMessagePreferredStyle")
  }
  addAction() {
    return geaAppleUIKitNativeOnly("UIAlertController.addAction")
  }
}

export class UIAction {
  static actionWithHandler() {
    return geaAppleUIKitNativeOnly("UIAction.actionWithHandler")
  }
}

export class ObjCTarget {
  static create() {
    return geaAppleUIKitNativeOnly("ObjCTarget.create")
  }
}

export class UIView {
  constructor() {
    geaAppleUIKitNativeOnly("new UIView")
  }
  addSubview() {
    return geaAppleUIKitNativeOnly("UIView.addSubview")
  }
  layoutIfNeeded() {
    return geaAppleUIKitNativeOnly("UIView.layoutIfNeeded")
  }
}

export class UIWindow {
}

export class UIControl {
  addTarget() {
    return geaAppleUIKitNativeOnly("UIControl.addTarget")
  }
  addAction() {
    return geaAppleUIKitNativeOnly("UIControl.addAction")
  }
}

export class UIButton {
  constructor() {
    geaAppleUIKitNativeOnly("new UIButton")
  }
  setTitle() {
    return geaAppleUIKitNativeOnly("UIButton.setTitle")
  }
  setTitleColor() {
    return geaAppleUIKitNativeOnly("UIButton.setTitleColor")
  }
}

export class UILabel {
  constructor() {
    geaAppleUIKitNativeOnly("new UILabel")
  }
}

export class UIImage {
  static systemImageNamed() {
    return geaAppleUIKitNativeOnly("UIImage.systemImageNamed")
  }
}

export class UIImageView {
  constructor() {
    geaAppleUIKitNativeOnly("new UIImageView")
  }
}

export class UIStackView {
  constructor() {
    geaAppleUIKitNativeOnly("new UIStackView")
  }
  addArrangedSubview() {
    return geaAppleUIKitNativeOnly("UIStackView.addArrangedSubview")
  }
}

export class UIBlurEffect {
  static effectWithStyle() {
    return geaAppleUIKitNativeOnly("UIBlurEffect.effectWithStyle")
  }
}

export class UIVisualEffectView {
  constructor() {
    geaAppleUIKitNativeOnly("new UIVisualEffectView")
  }
}

export class UISwitch {
  constructor() {
    geaAppleUIKitNativeOnly("new UISwitch")
  }
  setOn() {
    return geaAppleUIKitNativeOnly("UISwitch.setOn")
  }
}

export class UIProgressView {
  constructor() {
    geaAppleUIKitNativeOnly("new UIProgressView")
  }
}

export class UISlider {
  constructor() {
    geaAppleUIKitNativeOnly("new UISlider")
  }
}

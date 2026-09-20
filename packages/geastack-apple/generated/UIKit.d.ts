import type { NSObject, NSURL } from '@geastack/apple/Foundation'
import type { CGRect } from '@geastack/apple/CoreGraphics'
import type { CALayer } from '@geastack/apple/QuartzCore'

export type Selector = string

export declare const UIAlertActionStyleDefault: number
export declare const UIAlertActionStyleCancel: number
export declare const UIAlertActionStyleDestructive: number
export declare const UIAlertControllerStyleActionSheet: number
export declare const UIAlertControllerStyleAlert: number
export declare const UIModalPresentationFullScreen: number
export declare const UIControlEventTouchDown: number
export declare const UIControlEventTouchUpInside: number
export declare const UIControlEventTouchUpOutside: number
export declare const UIControlEventTouchCancel: number
export declare const UIControlEventValueChanged: number
export declare const ObjCTargetAction: Selector

export declare function installRootView(view: UIView): void

export declare class UIColor extends NSObject {
  static systemBackgroundColor(): UIColor
  static systemGroupedBackgroundColor(): UIColor
  static secondarySystemGroupedBackgroundColor(): UIColor
  static labelColor(): UIColor
  static secondaryLabelColor(): UIColor
  static systemBlueColor(): UIColor
  static systemIndigoColor(): UIColor
  static systemPurpleColor(): UIColor
  static systemTealColor(): UIColor
  static systemGreenColor(): UIColor
  static systemOrangeColor(): UIColor
  static systemGray5Color(): UIColor
  static whiteColor(): UIColor
  static blackColor(): UIColor
  static colorWithRed(red: number, green: number, blue: number, alpha: number): UIColor
  static colorWithRedGreenBlueAlpha(red: number, green: number, blue: number, alpha: number): UIColor
}

export declare class UIFont extends NSObject {
  static systemFontOfSize(fontSize: number): UIFont
  static systemFontOfSizeWeight(fontSize: number, weight: number): UIFont
  static boldSystemFontOfSize(fontSize: number): UIFont
}

export declare class UIScreen extends NSObject {
  readonly bounds: CGRect
  readonly scale: number
  static mainScreen(): UIScreen
}

export declare class UIApplication extends NSObject {
  readonly keyWindow: UIWindow
  static sharedApplication(): UIApplication
  openURL(url: NSURL): boolean
  openURLOptionsCompletionHandler(url: NSURL, options: NSDictionary, completionHandler: (success: boolean) => void): void
}

export declare class UIViewController extends NSObject {
  constructor()
  view: UIView
  title: string
  modalPresentationStyle: number
  presentViewControllerAnimatedCompletion(viewControllerToPresent: UIViewController, animated: boolean, completion: () => void): void
  dismissViewControllerAnimatedCompletion(animated: boolean, completion: () => void): void
}

export declare class UINavigationController extends UIViewController {
  constructor(rootViewController: UIViewController)
}

export declare class UIAlertAction extends NSObject {
  static actionWithTitleStyleHandler(title: string, style: number, handler: (action: UIAlertAction) => void): UIAlertAction
}

export declare class UIAlertController extends UIViewController {
  static alertControllerWithTitleMessagePreferredStyle(title: string, message: string, preferredStyle: number): UIAlertController
  addAction(action: UIAlertAction): void
}

export declare class UIAction extends NSObject {
  static actionWithHandler(handler: (action: UIAction) => void): UIAction
}

export declare class ObjCTarget {
  static create(callback: () => void): NSObject
}

export declare class UIView extends NSObject {
  constructor()
  frame: CGRect
  bounds: CGRect
  backgroundColor: UIColor | null
  tintColor: UIColor | null
  readonly layer: CALayer
  alpha: number
  hidden: boolean
  clipsToBounds: boolean
  userInteractionEnabled: boolean
  tag: number
  isAccessibilityElement: boolean
  accessibilityLabel: string
  addSubview(view: UIView): void
  layoutIfNeeded(): void
}

export declare class UIWindow extends UIView {
  rootViewController: UIViewController
}

export declare class UIControl extends UIView {
  addTarget(target: NSObject | null, action: Selector, controlEvents: number): void
  addAction(action: UIAction, controlEvents: number): void
}

export declare class UIButton extends UIControl {
  constructor()
  readonly titleLabel: UILabel
  setTitle(title: string, state: number): void
  setTitleColor(color: UIColor, state: number): void
}

export declare class UILabel extends UIView {
  constructor()
  text: string
  textColor: UIColor | null
  font: UIFont | null
  numberOfLines: number
  textAlignment: number
}

export declare class UIImage extends NSObject {
  static systemImageNamed(name: string): UIImage | null
}

export declare class UIImageView extends UIView {
  constructor()
  image: UIImage | null
  tintColor: UIColor | null
  contentMode: number
}

export declare class UIStackView extends UIView {
  constructor()
  axis: number
  alignment: number
  distribution: number
  spacing: number
  addArrangedSubview(view: UIView): void
}

export declare class UIBlurEffect extends NSObject {
  static effectWithStyle(style: number): UIBlurEffect
}

export declare class UIVisualEffectView extends UIView {
  constructor()
  effect: UIBlurEffect | null
  readonly contentView: UIView
}

export declare class UISwitch extends UIView {
  constructor()
  on: boolean
  onTintColor: UIColor | null
  thumbTintColor: UIColor | null
  setOn(on: boolean, animated: boolean): void
}

export declare class UIProgressView extends UIView {
  constructor()
  progress: number
  progressTintColor: UIColor | null
  trackTintColor: UIColor | null
}

export declare class UISlider extends UIControl {
  constructor()
  value: number
  minimumValue: number
  maximumValue: number
  continuous: boolean
  minimumTrackTintColor: UIColor | null
  maximumTrackTintColor: UIColor | null
  thumbTintColor: UIColor | null
}

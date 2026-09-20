function geaAppleAppKitNativeOnly(name) {
  throw new Error(`@geajs/apple/AppKit ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const NSViewNotSizable = 0
export const NSViewWidthSizable = 2
export const NSViewHeightSizable = 16
export const NSViewMinXMargin = 1
export const NSViewMaxXMargin = 4
export const NSViewMinYMargin = 8
export const NSViewMaxYMargin = 32
export const NSVisualEffectMaterialSidebar = 7
export const NSVisualEffectMaterialHeaderView = 10
export const NSVisualEffectMaterialContentBackground = 18
export const NSVisualEffectMaterialUnderWindowBackground = 21
export const NSVisualEffectBlendingModeBehindWindow = 0
export const NSVisualEffectBlendingModeWithinWindow = 1
export const NSVisualEffectStateFollowsWindowActiveState = 0
export const NSVisualEffectStateActive = 1
export const NSVisualEffectStateInactive = 2
export const NSSplitViewDividerStyleThick = 1
export const NSSplitViewDividerStyleThin = 2
export const NSSplitViewDividerStylePaneSplitter = 3
export const NSTextAlignmentLeft = 0
export const NSTextAlignmentRight = 1
export const NSTextAlignmentCenter = 2
export const NSLineBreakByWordWrapping = 0
export const NSLineBreakByTruncatingTail = 4
export const NSUserInterfaceLayoutOrientationHorizontal = 0
export const NSUserInterfaceLayoutOrientationVertical = 1
export const NSStackViewDistributionFill = 0
export const NSStackViewDistributionFillEqually = 1
export const NSStackViewDistributionFillProportionally = 2
export const NSStackViewDistributionEqualSpacing = 3
export const NSStackViewDistributionEqualCentering = 4
export const NSStackViewDistributionGravityAreas = -1
export const NSLayoutAttributeLeft = 1
export const NSLayoutAttributeRight = 2
export const NSLayoutAttributeTop = 3
export const NSLayoutAttributeBottom = 4
export const NSLayoutAttributeLeading = 5
export const NSLayoutAttributeTrailing = 6
export const NSLayoutAttributeWidth = 7
export const NSLayoutAttributeHeight = 8
export const NSLayoutAttributeCenterX = 9
export const NSLayoutAttributeCenterY = 10
export const NSLayoutConstraintOrientationHorizontal = 0
export const NSLayoutConstraintOrientationVertical = 1
export const NSLayoutPriorityRequired = 1000
export const NSLayoutPriorityDefaultHigh = 750
export const NSLayoutPriorityDefaultLow = 250
export const NSBoxCustom = 4
export const ObjCTargetAction = "invoke:"

export function installRootView() {
  return geaAppleAppKitNativeOnly("installRootView")
}

export function installRootViewController() {
  return geaAppleAppKitNativeOnly("installRootViewController")
}

export function installToolbar() {
  return geaAppleAppKitNativeOnly("installToolbar")
}

export function setScrollDocumentTopAligned() {
  return geaAppleAppKitNativeOnly("setScrollDocumentTopAligned")
}

export function runDeviceCommand() {
  return geaAppleAppKitNativeOnly("runDeviceCommand")
}

export class NSColor {
  static whiteColor() {
    return geaAppleAppKitNativeOnly("NSColor.whiteColor")
  }
  static blackColor() {
    return geaAppleAppKitNativeOnly("NSColor.blackColor")
  }
  static clearColor() {
    return geaAppleAppKitNativeOnly("NSColor.clearColor")
  }
  static labelColor() {
    return geaAppleAppKitNativeOnly("NSColor.labelColor")
  }
  static secondaryLabelColor() {
    return geaAppleAppKitNativeOnly("NSColor.secondaryLabelColor")
  }
  static tertiaryLabelColor() {
    return geaAppleAppKitNativeOnly("NSColor.tertiaryLabelColor")
  }
  static textColor() {
    return geaAppleAppKitNativeOnly("NSColor.textColor")
  }
  static controlBackgroundColor() {
    return geaAppleAppKitNativeOnly("NSColor.controlBackgroundColor")
  }
  static windowBackgroundColor() {
    return geaAppleAppKitNativeOnly("NSColor.windowBackgroundColor")
  }
  static separatorColor() {
    return geaAppleAppKitNativeOnly("NSColor.separatorColor")
  }
  static controlAccentColor() {
    return geaAppleAppKitNativeOnly("NSColor.controlAccentColor")
  }
  static systemBlueColor() {
    return geaAppleAppKitNativeOnly("NSColor.systemBlueColor")
  }
  static systemYellowColor() {
    return geaAppleAppKitNativeOnly("NSColor.systemYellowColor")
  }
  static colorWithSRGBRedGreenBlueAlpha() {
    return geaAppleAppKitNativeOnly("NSColor.colorWithSRGBRedGreenBlueAlpha")
  }
  static colorWithWhiteAlpha() {
    return geaAppleAppKitNativeOnly("NSColor.colorWithWhiteAlpha")
  }
}

export class NSLayoutConstraint {
}

export class NSLayoutXAxisAnchor {
  constraintEqualToAnchor() {
    return geaAppleAppKitNativeOnly("NSLayoutXAxisAnchor.constraintEqualToAnchor")
  }
  constraintEqualToAnchorConstant() {
    return geaAppleAppKitNativeOnly("NSLayoutXAxisAnchor.constraintEqualToAnchorConstant")
  }
}

export class NSLayoutYAxisAnchor {
  constraintEqualToAnchor() {
    return geaAppleAppKitNativeOnly("NSLayoutYAxisAnchor.constraintEqualToAnchor")
  }
  constraintEqualToAnchorConstant() {
    return geaAppleAppKitNativeOnly("NSLayoutYAxisAnchor.constraintEqualToAnchorConstant")
  }
}

export class NSLayoutDimension {
  constraintEqualToAnchor() {
    return geaAppleAppKitNativeOnly("NSLayoutDimension.constraintEqualToAnchor")
  }
  constraintEqualToConstant() {
    return geaAppleAppKitNativeOnly("NSLayoutDimension.constraintEqualToConstant")
  }
  constraintEqualToAnchorMultiplier() {
    return geaAppleAppKitNativeOnly("NSLayoutDimension.constraintEqualToAnchorMultiplier")
  }
}

export class NSLayoutGuide {
}

export class ObjCTarget {
  static create() {
    return geaAppleAppKitNativeOnly("ObjCTarget.create")
  }
}

export class NSClickGestureRecognizer {
  constructor(target, action) {
    geaAppleAppKitNativeOnly("new NSClickGestureRecognizer")
  }
}

export class NSView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSView")
  }
  addSubview() {
    return geaAppleAppKitNativeOnly("NSView.addSubview")
  }
  addGestureRecognizer() {
    return geaAppleAppKitNativeOnly("NSView.addGestureRecognizer")
  }
  setContentHuggingPriorityForOrientation() {
    return geaAppleAppKitNativeOnly("NSView.setContentHuggingPriorityForOrientation")
  }
  setContentCompressionResistancePriorityForOrientation() {
    return geaAppleAppKitNativeOnly("NSView.setContentCompressionResistancePriorityForOrientation")
  }
}

export class NSControl {
}

export class NSBox {
  constructor() {
    geaAppleAppKitNativeOnly("new NSBox")
  }
}

export class NSStackView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSStackView")
  }
  addArrangedSubview() {
    return geaAppleAppKitNativeOnly("NSStackView.addArrangedSubview")
  }
  insertArrangedSubviewAtIndex() {
    return geaAppleAppKitNativeOnly("NSStackView.insertArrangedSubviewAtIndex")
  }
  setHuggingPriorityForOrientation() {
    return geaAppleAppKitNativeOnly("NSStackView.setHuggingPriorityForOrientation")
  }
}

export class NSTextField {
  constructor() {
    geaAppleAppKitNativeOnly("new NSTextField")
  }
  attachTextDelegate() {
    return geaAppleAppKitNativeOnly("NSTextField.attachTextDelegate")
  }
}

export class NSFont {
  static systemFontOfSize() {
    return geaAppleAppKitNativeOnly("NSFont.systemFontOfSize")
  }
  static boldSystemFontOfSize() {
    return geaAppleAppKitNativeOnly("NSFont.boldSystemFontOfSize")
  }
  static systemFontOfSizeWeight() {
    return geaAppleAppKitNativeOnly("NSFont.systemFontOfSizeWeight")
  }
}

export class NSVisualEffectView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSVisualEffectView")
  }
}

export class NSScrollView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSScrollView")
  }
}

export class NSSplitView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSSplitView")
  }
  addArrangedSubview() {
    return geaAppleAppKitNativeOnly("NSSplitView.addArrangedSubview")
  }
  adjustSubviews() {
    return geaAppleAppKitNativeOnly("NSSplitView.adjustSubviews")
  }
  setPositionOfDividerAtIndex() {
    return geaAppleAppKitNativeOnly("NSSplitView.setPositionOfDividerAtIndex")
  }
}

export class NSTextView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSTextView")
  }
  attachTextDelegate() {
    return geaAppleAppKitNativeOnly("NSTextView.attachTextDelegate")
  }
}

export class NSImage {
  static imageWithSystemSymbolNameAccessibilityDescription() {
    return geaAppleAppKitNativeOnly("NSImage.imageWithSystemSymbolNameAccessibilityDescription")
  }
}

export class NSImageView {
  constructor() {
    geaAppleAppKitNativeOnly("new NSImageView")
  }
}

export class NSButton {
  constructor() {
    geaAppleAppKitNativeOnly("new NSButton")
  }
}

export class NSViewController {
  constructor() {
    geaAppleAppKitNativeOnly("new NSViewController")
  }
}

export class NSSplitViewController {
  constructor() {
    geaAppleAppKitNativeOnly("new NSSplitViewController")
  }
  addSplitViewItem() {
    return geaAppleAppKitNativeOnly("NSSplitViewController.addSplitViewItem")
  }
}

export class NSSplitViewItem {
  static sidebarWithViewController() {
    return geaAppleAppKitNativeOnly("NSSplitViewItem.sidebarWithViewController")
  }
  static contentListWithViewController() {
    return geaAppleAppKitNativeOnly("NSSplitViewItem.contentListWithViewController")
  }
  static splitViewItemWithViewController() {
    return geaAppleAppKitNativeOnly("NSSplitViewItem.splitViewItemWithViewController")
  }
}

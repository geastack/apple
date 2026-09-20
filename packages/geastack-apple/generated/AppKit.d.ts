import type { NSObject } from '@geastack/apple/Foundation'
import type { CGRect } from '@geastack/apple/CoreGraphics'
import type { CALayer } from '@geastack/apple/QuartzCore'

export type Selector = string

export declare const NSViewNotSizable: number
export declare const NSViewWidthSizable: number
export declare const NSViewHeightSizable: number
export declare const NSViewMinXMargin: number
export declare const NSViewMaxXMargin: number
export declare const NSViewMinYMargin: number
export declare const NSViewMaxYMargin: number
export declare const NSVisualEffectMaterialSidebar: number
export declare const NSVisualEffectMaterialHeaderView: number
export declare const NSVisualEffectMaterialContentBackground: number
export declare const NSVisualEffectMaterialUnderWindowBackground: number
export declare const NSVisualEffectBlendingModeBehindWindow: number
export declare const NSVisualEffectBlendingModeWithinWindow: number
export declare const NSVisualEffectStateFollowsWindowActiveState: number
export declare const NSVisualEffectStateActive: number
export declare const NSVisualEffectStateInactive: number
export declare const NSSplitViewDividerStyleThick: number
export declare const NSSplitViewDividerStyleThin: number
export declare const NSSplitViewDividerStylePaneSplitter: number
export declare const NSTextAlignmentLeft: number
export declare const NSTextAlignmentRight: number
export declare const NSTextAlignmentCenter: number
export declare const NSLineBreakByWordWrapping: number
export declare const NSLineBreakByTruncatingTail: number
export declare const NSUserInterfaceLayoutOrientationHorizontal: number
export declare const NSUserInterfaceLayoutOrientationVertical: number
export declare const NSStackViewDistributionFill: number
export declare const NSStackViewDistributionFillEqually: number
export declare const NSStackViewDistributionFillProportionally: number
export declare const NSStackViewDistributionEqualSpacing: number
export declare const NSStackViewDistributionEqualCentering: number
export declare const NSStackViewDistributionGravityAreas: number
export declare const NSLayoutAttributeLeft: number
export declare const NSLayoutAttributeRight: number
export declare const NSLayoutAttributeTop: number
export declare const NSLayoutAttributeBottom: number
export declare const NSLayoutAttributeLeading: number
export declare const NSLayoutAttributeTrailing: number
export declare const NSLayoutAttributeWidth: number
export declare const NSLayoutAttributeHeight: number
export declare const NSLayoutAttributeCenterX: number
export declare const NSLayoutAttributeCenterY: number
export declare const NSLayoutConstraintOrientationHorizontal: number
export declare const NSLayoutConstraintOrientationVertical: number
export declare const NSLayoutPriorityRequired: number
export declare const NSLayoutPriorityDefaultHigh: number
export declare const NSLayoutPriorityDefaultLow: number
export declare const NSBoxCustom: number
export declare const ObjCTargetAction: Selector

export declare function installRootView(view: NSView): void
export declare function installRootViewController(viewController: NSViewController): void
export declare function installToolbar(spec: string, newNoteTarget: NSObject | null): void
export declare function setScrollDocumentTopAligned(scrollView: NSScrollView, content: NSView): void
export declare function runDeviceCommand(command: string): string

export declare class NSColor extends NSObject {
  static whiteColor(): NSColor
  static blackColor(): NSColor
  static clearColor(): NSColor
  static labelColor(): NSColor
  static secondaryLabelColor(): NSColor
  static tertiaryLabelColor(): NSColor
  static textColor(): NSColor
  static controlBackgroundColor(): NSColor
  static windowBackgroundColor(): NSColor
  static separatorColor(): NSColor
  static controlAccentColor(): NSColor
  static systemBlueColor(): NSColor
  static systemYellowColor(): NSColor
  static colorWithSRGBRedGreenBlueAlpha(red: number, green: number, blue: number, alpha: number): NSColor
  static colorWithWhiteAlpha(white: number, alpha: number): NSColor
}

export declare class NSLayoutConstraint extends NSObject {
  active: boolean
}

export declare class NSLayoutXAxisAnchor extends NSObject {
  constraintEqualToAnchor(anchor: NSLayoutXAxisAnchor): NSLayoutConstraint
  constraintEqualToAnchorConstant(anchor: NSLayoutXAxisAnchor, constant: number): NSLayoutConstraint
}

export declare class NSLayoutYAxisAnchor extends NSObject {
  constraintEqualToAnchor(anchor: NSLayoutYAxisAnchor): NSLayoutConstraint
  constraintEqualToAnchorConstant(anchor: NSLayoutYAxisAnchor, constant: number): NSLayoutConstraint
}

export declare class NSLayoutDimension extends NSObject {
  constraintEqualToAnchor(anchor: NSLayoutDimension): NSLayoutConstraint
  constraintEqualToConstant(constant: number): NSLayoutConstraint
  constraintEqualToAnchorMultiplier(anchor: NSLayoutDimension, multiplier: number): NSLayoutConstraint
}

export declare class NSLayoutGuide extends NSObject {
  readonly leadingAnchor: NSLayoutXAxisAnchor
  readonly trailingAnchor: NSLayoutXAxisAnchor
  readonly topAnchor: NSLayoutYAxisAnchor
  readonly bottomAnchor: NSLayoutYAxisAnchor
}

export declare class ObjCTarget {
  static create(callback: () => void): NSObject
}

export declare class NSClickGestureRecognizer extends NSObject {
  constructor(target: NSObject | null, action: Selector)
  numberOfClicksRequired: number
}

export declare class NSView extends NSObject {
  constructor()
  frame: CGRect
  readonly bounds: CGRect
  wantsLayer: boolean
  readonly layer: CALayer
  hidden: boolean
  alphaValue: number
  autoresizingMask: number
  translatesAutoresizingMaskIntoConstraints: boolean
  readonly leadingAnchor: NSLayoutXAxisAnchor
  readonly trailingAnchor: NSLayoutXAxisAnchor
  readonly centerXAnchor: NSLayoutXAxisAnchor
  readonly topAnchor: NSLayoutYAxisAnchor
  readonly bottomAnchor: NSLayoutYAxisAnchor
  readonly centerYAnchor: NSLayoutYAxisAnchor
  readonly widthAnchor: NSLayoutDimension
  readonly heightAnchor: NSLayoutDimension
  readonly safeAreaLayoutGuide: NSLayoutGuide
  addSubview(view: NSView): void
  addGestureRecognizer(recognizer: NSObject): void
  setContentHuggingPriorityForOrientation(priority: number, orientation: number): void
  setContentCompressionResistancePriorityForOrientation(priority: number, orientation: number): void
}

export declare class NSControl extends NSView {
  target: NSObject | null
  action: Selector
  enabled: boolean
}

export declare class NSBox extends NSView {
  constructor()
  boxType: number
  borderWidth: number
  cornerRadius: number
  fillColor: NSColor | null
  borderColor: NSColor | null
  titlePosition: number
  contentView: NSView | null
}

export declare class NSStackView extends NSView {
  constructor()
  orientation: number
  spacing: number
  alignment: number
  distribution: number
  detachesHiddenViews: boolean
  addArrangedSubview(view: NSView): void
  insertArrangedSubviewAtIndex(view: NSView, index: number): void
  setHuggingPriorityForOrientation(priority: number, orientation: number): void
}

export declare class NSTextField extends NSView {
  constructor()
  stringValue: string
  placeholderString: string
  editable: boolean
  selectable: boolean
  bezeled: boolean
  bordered: boolean
  drawsBackground: boolean
  backgroundColor: NSColor | null
  textColor: NSColor | null
  font: NSFont | null
  alignment: number
  lineBreakMode: number
  maximumNumberOfLines: number
  attachTextDelegate(delegate: NSObject | null): void
}

export declare class NSFont extends NSObject {
  static systemFontOfSize(fontSize: number): NSFont
  static boldSystemFontOfSize(fontSize: number): NSFont
  static systemFontOfSizeWeight(fontSize: number, weight: number): NSFont
}

export declare class NSVisualEffectView extends NSView {
  constructor()
  material: number
  blendingMode: number
  state: number
  emphasized: boolean
}

export declare class NSScrollView extends NSView {
  constructor()
  documentView: NSView | null
  hasVerticalScroller: boolean
  hasHorizontalScroller: boolean
  drawsBackground: boolean
  automaticallyAdjustsContentInsets: boolean
}

export declare class NSSplitView extends NSView {
  constructor()
  vertical: boolean
  dividerStyle: number
  addArrangedSubview(view: NSView): void
  adjustSubviews(): void
  setPositionOfDividerAtIndex(position: number, dividerIndex: number): void
}

export declare class NSTextView extends NSView {
  constructor()
  string: string
  editable: boolean
  selectable: boolean
  drawsBackground: boolean
  backgroundColor: NSColor | null
  textColor: NSColor | null
  font: NSFont | null
  attachTextDelegate(delegate: NSObject | null): void
}

export declare class NSImage extends NSObject {
  static imageWithSystemSymbolNameAccessibilityDescription(symbolName: string, accessibilityDescription: string): NSImage | null
}

export declare class NSImageView extends NSView {
  constructor()
  image: NSImage | null
  contentTintColor: NSColor | null
}

export declare class NSButton extends NSControl {
  constructor()
  title: string
  bordered: boolean
}

export declare class NSViewController extends NSObject {
  constructor()
  view: NSView
  title: string
}

export declare class NSSplitViewController extends NSViewController {
  constructor()
  addSplitViewItem(item: NSSplitViewItem): void
}

export declare class NSSplitViewItem extends NSObject {
  minimumThickness: number
  maximumThickness: number
  canCollapse: boolean
  preferredThicknessFraction: number
  static sidebarWithViewController(viewController: NSViewController): NSSplitViewItem
  static contentListWithViewController(viewController: NSViewController): NSSplitViewItem
  static splitViewItemWithViewController(viewController: NSViewController): NSSplitViewItem
}

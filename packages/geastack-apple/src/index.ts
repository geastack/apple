export type ApplePrimitiveType = 'boolean' | 'number' | 'string' | 'void' | 'selector'

export type AppleTypeReference =
  | {
      kind: 'primitive' | 'class' | 'struct'
      name: string
      nullable?: boolean
    }
  | {
      kind: 'array'
      element: AppleTypeReference
      nullable?: boolean
    }
  | {
      kind: 'function'
      returns: AppleTypeReference
      parameters?: AppleParameterDefinition[]
      nullable?: boolean
    }

export interface AppleParameterDefinition {
  name: string
  type: AppleTypeReference
}

export interface AppleMethodDefinition {
  name: string
  selector: string
  returns: AppleTypeReference
  parameters?: AppleParameterDefinition[]
  static?: boolean
}

export interface ApplePropertyDefinition {
  name: string
  type: AppleTypeReference
  readonly?: boolean
}

export interface AppleFunctionDefinition {
  name: string
  returns: AppleTypeReference
  parameters?: AppleParameterDefinition[]
}

export interface AppleConstantDefinition {
  name: string
  type: AppleTypeReference
  value: string | number | boolean
}

export interface AppleClassDefinition {
  name: string
  extends?: string
  constructors?: AppleMethodDefinition[]
  methods?: AppleMethodDefinition[]
  properties?: ApplePropertyDefinition[]
}

export interface AppleStructDefinition {
  name: string
  fields: AppleParameterDefinition[]
}

export interface AppleFrameworkDefinition {
  name: string
  bridgeHeaders?: string[]
  imports?: Record<string, string[]>
  constants?: AppleConstantDefinition[]
  functions?: AppleFunctionDefinition[]
  classes?: AppleClassDefinition[]
  structs?: AppleStructDefinition[]
}

export interface AppleSdkDefinition {
  frameworks: AppleFrameworkDefinition[]
}

export interface AppleBridgeMetadata {
  frameworks: Array<{ name: string; bridgeHeaders?: string[] }>
  constants: Record<string, AppleBridgeConstantMetadata>
  functions: Record<string, AppleBridgeFunctionMetadata>
  classes: Record<string, AppleBridgeClassMetadata>
  structs: Record<string, AppleBridgeStructMetadata>
}

export interface AppleBridgeConstantMetadata {
  framework: string
  name: string
  type: AppleTypeReference
  value: string | number | boolean
}

export interface AppleBridgeFunctionMetadata {
  framework: string
  name: string
  thunk: string
  returns: AppleTypeReference
  parameters: AppleParameterDefinition[]
}

export interface AppleBridgeClassMetadata {
  framework: string
  name: string
  extends?: string
  wrapper: string
  constructor?: AppleBridgeConstructorMetadata
  methods: Record<string, AppleBridgeMethodMetadata>
  properties: Record<string, AppleBridgePropertyMetadata>
}

export interface AppleBridgeConstructorMetadata {
  selector: string
  thunk: string
  parameters?: AppleParameterDefinition[]
}

export interface AppleBridgeMethodMetadata {
  name: string
  selector: string
  thunk: string
  returns: AppleTypeReference
  parameters: AppleParameterDefinition[]
  static?: boolean
}

export interface AppleBridgePropertyMetadata {
  name: string
  getter: string
  setter?: string
  type: AppleTypeReference
}

export interface AppleBridgeStructMetadata {
  framework: string
  name: string
  wrapper: string
  fields: AppleParameterDefinition[]
}

const objcFrameworkImports: Record<string, string> = {
  AVFoundation: 'AVFoundation/AVFoundation.h',
  CoreMedia: 'CoreMedia/CoreMedia.h',
  CoreLocation: 'CoreLocation/CoreLocation.h',
  Dispatch: 'dispatch/dispatch.h',
  Foundation: 'Foundation/Foundation.h',
  MapKit: 'MapKit/MapKit.h',
  Metal: 'Metal/Metal.h',
  MetalKit: 'MetalKit/MetalKit.h',
  Photos: 'Photos/Photos.h',
  QuartzCore: 'QuartzCore/QuartzCore.h',
  UIKit: 'UIKit/UIKit.h',
  AppKit: 'AppKit/AppKit.h',
}

const voidType: AppleTypeReference = { kind: 'primitive', name: 'void' }
const stringType: AppleTypeReference = { kind: 'primitive', name: 'string' }
const numberType: AppleTypeReference = { kind: 'primitive', name: 'number' }
const selectorType: AppleTypeReference = { kind: 'primitive', name: 'selector' }
const controlEventsType: AppleTypeReference = { kind: 'primitive', name: 'UIControlEvents' }
const textAlignmentType: AppleTypeReference = { kind: 'primitive', name: 'NSTextAlignment' }
// NSLayoutConstraintOrientation is an NS_ENUM; model it as a named primitive (not
// `number`) so the apple-native lowering emits the explicit int->enum static_cast
// for method args (e.g. setContentHuggingPriority:forOrientation:). A bare `number`
// arg fails to compile ("cannot initialize NSLayoutConstraintOrientation from int").
const layoutConstraintOrientationType: AppleTypeReference = { kind: 'primitive', name: 'NSLayoutConstraintOrientation' }
const viewContentModeType: AppleTypeReference = { kind: 'primitive', name: 'UIViewContentMode' }
const layoutConstraintAxisType: AppleTypeReference = { kind: 'primitive', name: 'UILayoutConstraintAxis' }
const stackViewAlignmentType: AppleTypeReference = { kind: 'primitive', name: 'UIStackViewAlignment' }
const stackViewDistributionType: AppleTypeReference = { kind: 'primitive', name: 'UIStackViewDistribution' }
const alertActionStyleType: AppleTypeReference = { kind: 'primitive', name: 'UIAlertActionStyle' }
const alertControllerStyleType: AppleTypeReference = { kind: 'primitive', name: 'UIAlertControllerStyle' }
const modalPresentationStyleType: AppleTypeReference = { kind: 'primitive', name: 'UIModalPresentationStyle' }
const mapTypeType: AppleTypeReference = { kind: 'primitive', name: 'MKMapType' }
const userTrackingModeType: AppleTypeReference = { kind: 'primitive', name: 'MKUserTrackingMode' }
const captureFocusModeType: AppleTypeReference = { kind: 'primitive', name: 'AVCaptureFocusMode' }
const captureExposureModeType: AppleTypeReference = { kind: 'primitive', name: 'AVCaptureExposureMode' }
const captureDevicePositionType: AppleTypeReference = { kind: 'primitive', name: 'AVCaptureDevicePosition' }
const captureFlashModeType: AppleTypeReference = { kind: 'primitive', name: 'AVCaptureFlashMode' }
const capturePhotoQualityPrioritizationType: AppleTypeReference = { kind: 'primitive', name: 'AVCapturePhotoQualityPrioritization' }
const captureWhiteBalanceModeType: AppleTypeReference = { kind: 'primitive', name: 'AVCaptureWhiteBalanceMode' }
const metalPixelFormatType: AppleTypeReference = numberType
const metalPrimitiveType: AppleTypeReference = numberType
const metalResourceOptionsType: AppleTypeReference = numberType
const metalCompareFunctionType: AppleTypeReference = numberType
const numberArrayType: AppleTypeReference = { kind: 'array', element: numberType }
const voidCallbackType: AppleTypeReference = { kind: 'function', returns: voidType, parameters: [] }
const uiActionHandlerType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [{ name: 'action', type: { kind: 'class', name: 'UIKit.UIAction' } }],
}
const uiAlertActionHandlerType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [{ name: 'action', type: { kind: 'class', name: 'UIKit.UIAlertAction' } }],
}
const photoCaptureHandlerType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [
    { name: 'data', type: { kind: 'class', name: 'Foundation.NSData' } },
    { name: 'error', type: stringType },
  ],
}
const photoLibrarySaveHandlerType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [
    { name: 'success', type: { kind: 'primitive', name: 'boolean' } },
    { name: 'error', type: stringType },
  ],
}
const urlOpenCompletionHandlerType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [{ name: 'success', type: { kind: 'primitive', name: 'boolean' } }],
}
const cmtimeCallbackType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [{ name: 'syncTime', type: { kind: 'struct', name: 'CoreMedia.CMTime' } }],
}
const mtkViewDrawCallbackType: AppleTypeReference = {
  kind: 'function',
  returns: voidType,
  parameters: [],
}

const nativeStructFrameworks = new Set(['CoreGraphics', 'CoreLocation', 'CoreMedia', 'MapKit'])

export const appleSdkFixture: AppleSdkDefinition = {
  frameworks: [
    {
      name: 'Foundation',
      classes: [
        { name: 'NSObject' },
        { name: 'NSData', extends: 'Foundation.NSObject' },
        {
          name: 'NSDictionary',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'dictionary',
              selector: 'dictionary',
              static: true,
              returns: { kind: 'class', name: 'Foundation.NSDictionary' },
            },
          ],
        },
        {
          name: 'NSURL',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'URLWithString',
              selector: 'URLWithString:',
              static: true,
              returns: { kind: 'class', name: 'Foundation.NSURL', nullable: true },
              parameters: [{ name: 'URLString', type: stringType }],
            },
          ],
        },
      ],
    },
    {
      name: 'Dispatch',
      functions: [
        {
          name: 'dispatchAsyncGlobal',
          returns: voidType,
          parameters: [{ name: 'execute', type: voidCallbackType }],
        },
        {
          name: 'dispatchAsyncMain',
          returns: voidType,
          parameters: [{ name: 'execute', type: voidCallbackType }],
        },
      ],
    },
    {
      name: 'CoreGraphics',
      functions: [
        {
          name: 'CGRectMake',
          returns: { kind: 'struct', name: 'CoreGraphics.CGRect' },
          parameters: [
            { name: 'x', type: numberType },
            { name: 'y', type: numberType },
            { name: 'width', type: numberType },
            { name: 'height', type: numberType },
          ],
        },
        {
          name: 'CGPointMake',
          returns: { kind: 'struct', name: 'CoreGraphics.CGPoint' },
          parameters: [
            { name: 'x', type: numberType },
            { name: 'y', type: numberType },
          ],
        },
        {
          name: 'CGSizeMake',
          returns: { kind: 'struct', name: 'CoreGraphics.CGSize' },
          parameters: [
            { name: 'width', type: numberType },
            { name: 'height', type: numberType },
          ],
        },
      ],
      structs: [
        {
          name: 'CGPoint',
          fields: [
            { name: 'x', type: numberType },
            { name: 'y', type: numberType },
          ],
        },
        {
          name: 'CGSize',
          fields: [
            { name: 'width', type: numberType },
            { name: 'height', type: numberType },
          ],
        },
        {
          name: 'CGRect',
          fields: [
            { name: 'origin', type: { kind: 'struct', name: 'CoreGraphics.CGPoint' } },
            { name: 'size', type: { kind: 'struct', name: 'CoreGraphics.CGSize' } },
          ],
        },
      ],
    },
    {
      name: 'QuartzCore',
      imports: {
        Foundation: ['NSObject'],
        CoreGraphics: ['CGSize'],
      },
      classes: [
        {
          name: 'CALayer',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'frame', type: { kind: 'struct', name: 'CoreGraphics.CGRect' } },
            { name: 'cornerRadius', type: numberType },
            { name: 'shadowOpacity', type: numberType },
            { name: 'shadowRadius', type: numberType },
            { name: 'shadowOffset', type: { kind: 'struct', name: 'CoreGraphics.CGSize' } },
            { name: 'masksToBounds', type: { kind: 'primitive', name: 'boolean' } },
          ],
          methods: [
            {
              name: 'addSublayer',
              selector: 'addSublayer:',
              returns: voidType,
              parameters: [{ name: 'layer', type: { kind: 'class', name: 'QuartzCore.CALayer' } }],
            },
          ],
        },
      ],
    },
    {
      name: 'UIKit',
      imports: {
        Foundation: ['NSObject', 'NSURL'],
        CoreGraphics: ['CGRect'],
        QuartzCore: ['CALayer'],
      },
      constants: [
        { name: 'UIAlertActionStyleDefault', type: alertActionStyleType, value: 0 },
        { name: 'UIAlertActionStyleCancel', type: alertActionStyleType, value: 1 },
        { name: 'UIAlertActionStyleDestructive', type: alertActionStyleType, value: 2 },
        { name: 'UIAlertControllerStyleActionSheet', type: alertControllerStyleType, value: 0 },
        { name: 'UIAlertControllerStyleAlert', type: alertControllerStyleType, value: 1 },
        { name: 'UIModalPresentationFullScreen', type: modalPresentationStyleType, value: 0 },
        { name: 'UIControlEventTouchDown', type: controlEventsType, value: 1 },
        { name: 'UIControlEventTouchUpInside', type: controlEventsType, value: 64 },
        { name: 'UIControlEventTouchUpOutside', type: controlEventsType, value: 128 },
        { name: 'UIControlEventTouchCancel', type: controlEventsType, value: 256 },
        { name: 'UIControlEventValueChanged', type: controlEventsType, value: 4096 },
        { name: 'ObjCTargetAction', type: selectorType, value: 'invoke:' },
      ],
      classes: [
        {
          name: 'UIColor',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'systemBackgroundColor',
              selector: 'systemBackgroundColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemGroupedBackgroundColor',
              selector: 'systemGroupedBackgroundColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'secondarySystemGroupedBackgroundColor',
              selector: 'secondarySystemGroupedBackgroundColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'labelColor',
              selector: 'labelColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'secondaryLabelColor',
              selector: 'secondaryLabelColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemBlueColor',
              selector: 'systemBlueColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemIndigoColor',
              selector: 'systemIndigoColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemPurpleColor',
              selector: 'systemPurpleColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemTealColor',
              selector: 'systemTealColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemGreenColor',
              selector: 'systemGreenColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemOrangeColor',
              selector: 'systemOrangeColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'systemGray5Color',
              selector: 'systemGray5Color',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'whiteColor',
              selector: 'whiteColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'blackColor',
              selector: 'blackColor',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
            },
            {
              name: 'colorWithRed',
              selector: 'colorWithRed:green:blue:alpha:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
              parameters: [
                { name: 'red', type: numberType },
                { name: 'green', type: numberType },
                { name: 'blue', type: numberType },
                { name: 'alpha', type: numberType },
              ],
            },
            {
              name: 'colorWithRedGreenBlueAlpha',
              selector: 'colorWithRed:green:blue:alpha:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIColor' },
              parameters: [
                { name: 'red', type: numberType },
                { name: 'green', type: numberType },
                { name: 'blue', type: numberType },
                { name: 'alpha', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'UIFont',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'systemFontOfSize',
              selector: 'systemFontOfSize:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIFont' },
              parameters: [{ name: 'fontSize', type: numberType }],
            },
            {
              name: 'systemFontOfSizeWeight',
              selector: 'systemFontOfSize:weight:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIFont' },
              parameters: [
                { name: 'fontSize', type: numberType },
                { name: 'weight', type: numberType },
              ],
            },
            {
              name: 'boldSystemFontOfSize',
              selector: 'boldSystemFontOfSize:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIFont' },
              parameters: [{ name: 'fontSize', type: numberType }],
            },
          ],
        },
        {
          name: 'UIScreen',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'bounds', type: { kind: 'struct', name: 'CoreGraphics.CGRect' }, readonly: true },
            { name: 'scale', type: numberType, readonly: true },
          ],
          methods: [
            {
              name: 'mainScreen',
              selector: 'mainScreen',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIScreen' },
            },
          ],
        },
        {
          name: 'UIApplication',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'keyWindow', type: { kind: 'class', name: 'UIKit.UIWindow' }, readonly: true },
          ],
          methods: [
            {
              name: 'sharedApplication',
              selector: 'sharedApplication',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIApplication' },
            },
            {
              name: 'openURL',
              selector: 'openURL:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'url', type: { kind: 'class', name: 'Foundation.NSURL' } }],
            },
            {
              name: 'openURLOptionsCompletionHandler',
              selector: 'openURL:options:completionHandler:',
              returns: voidType,
              parameters: [
                { name: 'url', type: { kind: 'class', name: 'Foundation.NSURL' } },
                { name: 'options', type: { kind: 'class', name: 'Foundation.NSDictionary' } },
                { name: 'completionHandler', type: urlOpenCompletionHandlerType },
              ],
            },
          ],
        },
        {
          name: 'UIViewController',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIViewController' } }],
          properties: [
            { name: 'view', type: { kind: 'class', name: 'UIKit.UIView' } },
            { name: 'title', type: stringType },
            { name: 'modalPresentationStyle', type: modalPresentationStyleType },
          ],
          methods: [
            {
              name: 'presentViewControllerAnimatedCompletion',
              selector: 'presentViewController:animated:completion:',
              returns: voidType,
              parameters: [
                { name: 'viewControllerToPresent', type: { kind: 'class', name: 'UIKit.UIViewController' } },
                { name: 'animated', type: { kind: 'primitive', name: 'boolean' } },
                { name: 'completion', type: voidCallbackType },
              ],
            },
            {
              name: 'dismissViewControllerAnimatedCompletion',
              selector: 'dismissViewControllerAnimated:completion:',
              returns: voidType,
              parameters: [
                { name: 'animated', type: { kind: 'primitive', name: 'boolean' } },
                { name: 'completion', type: voidCallbackType },
              ],
            },
          ],
        },
        {
          name: 'UINavigationController',
          extends: 'UIKit.UIViewController',
          constructors: [
            {
              name: 'initWithRootViewController',
              selector: 'initWithRootViewController:',
              returns: { kind: 'class', name: 'UIKit.UINavigationController' },
              parameters: [{ name: 'rootViewController', type: { kind: 'class', name: 'UIKit.UIViewController' } }],
            },
          ],
        },
        {
          name: 'UIAlertAction',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'actionWithTitleStyleHandler',
              selector: 'actionWithTitle:style:handler:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIAlertAction' },
              parameters: [
                { name: 'title', type: stringType },
                { name: 'style', type: alertActionStyleType },
                { name: 'handler', type: uiAlertActionHandlerType },
              ],
            },
          ],
        },
        {
          name: 'UIAlertController',
          extends: 'UIKit.UIViewController',
          methods: [
            {
              name: 'alertControllerWithTitleMessagePreferredStyle',
              selector: 'alertControllerWithTitle:message:preferredStyle:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIAlertController' },
              parameters: [
                { name: 'title', type: stringType },
                { name: 'message', type: stringType },
                { name: 'preferredStyle', type: alertControllerStyleType },
              ],
            },
            {
              name: 'addAction',
              selector: 'addAction:',
              returns: voidType,
              parameters: [{ name: 'action', type: { kind: 'class', name: 'UIKit.UIAlertAction' } }],
            },
          ],
        },
        {
          name: 'UIAction',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'actionWithHandler',
              selector: 'actionWithHandler:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIAction' },
              parameters: [{ name: 'handler', type: uiActionHandlerType }],
            },
          ],
        },
        {
          name: 'ObjCTarget',
          methods: [
            {
              name: 'create',
              selector: 'create:',
              static: true,
              returns: { kind: 'class', name: 'Foundation.NSObject' },
              parameters: [{ name: 'callback', type: voidCallbackType }],
            },
          ],
        },
        {
          name: 'UIView',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIView' } }],
          properties: [
            { name: 'frame', type: { kind: 'struct', name: 'CoreGraphics.CGRect' } },
            { name: 'bounds', type: { kind: 'struct', name: 'CoreGraphics.CGRect' } },
            { name: 'backgroundColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'tintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'layer', type: { kind: 'class', name: 'QuartzCore.CALayer' }, readonly: true },
            { name: 'alpha', type: numberType },
            { name: 'hidden', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'clipsToBounds', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'userInteractionEnabled', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'tag', type: numberType },
            { name: 'isAccessibilityElement', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'accessibilityLabel', type: stringType },
          ],
          methods: [
            {
              name: 'addSubview',
              selector: 'addSubview:',
              returns: voidType,
              parameters: [{ name: 'view', type: { kind: 'class', name: 'UIKit.UIView' } }],
            },
            {
              name: 'layoutIfNeeded',
              selector: 'layoutIfNeeded',
              returns: voidType,
            },
          ],
        },
        {
          name: 'UIWindow',
          extends: 'UIKit.UIView',
          properties: [
            { name: 'rootViewController', type: { kind: 'class', name: 'UIKit.UIViewController' } },
          ],
        },
        {
          name: 'UIControl',
          extends: 'UIKit.UIView',
          methods: [
            {
              name: 'addTarget',
              selector: 'addTarget:action:forControlEvents:',
              returns: voidType,
              parameters: [
                { name: 'target', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } },
                { name: 'action', type: selectorType },
                { name: 'controlEvents', type: controlEventsType },
              ],
            },
            {
              name: 'addAction',
              selector: 'addAction:forControlEvents:',
              returns: voidType,
              parameters: [
                { name: 'action', type: { kind: 'class', name: 'UIKit.UIAction' } },
                { name: 'controlEvents', type: controlEventsType },
              ],
            },
          ],
        },
        {
          name: 'UIButton',
          extends: 'UIKit.UIControl',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIButton' } }],
          methods: [
            {
              name: 'setTitle',
              selector: 'setTitle:forState:',
              returns: voidType,
              parameters: [
                { name: 'title', type: stringType },
                { name: 'state', type: numberType },
              ],
            },
            {
              name: 'setTitleColor',
              selector: 'setTitleColor:forState:',
              returns: voidType,
              parameters: [
                { name: 'color', type: { kind: 'class', name: 'UIKit.UIColor' } },
                { name: 'state', type: numberType },
              ],
            },
          ],
          properties: [{ name: 'titleLabel', type: { kind: 'class', name: 'UIKit.UILabel' }, readonly: true }],
        },
        {
          name: 'UILabel',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UILabel' } }],
          properties: [
            { name: 'text', type: stringType },
            { name: 'textColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'font', type: { kind: 'class', name: 'UIKit.UIFont', nullable: true } },
            { name: 'numberOfLines', type: numberType },
            { name: 'textAlignment', type: textAlignmentType },
          ],
        },
        {
          name: 'UIImage',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'systemImageNamed',
              selector: 'systemImageNamed:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIImage', nullable: true },
              parameters: [{ name: 'name', type: stringType }],
            },
          ],
        },
        {
          name: 'UIImageView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIImageView' } }],
          properties: [
            { name: 'image', type: { kind: 'class', name: 'UIKit.UIImage', nullable: true } },
            { name: 'tintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'contentMode', type: viewContentModeType },
          ],
        },
        {
          name: 'UIStackView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIStackView' } }],
          properties: [
            { name: 'axis', type: layoutConstraintAxisType },
            { name: 'alignment', type: stackViewAlignmentType },
            { name: 'distribution', type: stackViewDistributionType },
            { name: 'spacing', type: numberType },
          ],
          methods: [
            {
              name: 'addArrangedSubview',
              selector: 'addArrangedSubview:',
              returns: voidType,
              parameters: [{ name: 'view', type: { kind: 'class', name: 'UIKit.UIView' } }],
            },
          ],
        },
        {
          name: 'UIBlurEffect',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'effectWithStyle',
              selector: 'effectWithStyle:',
              static: true,
              returns: { kind: 'class', name: 'UIKit.UIBlurEffect' },
              parameters: [{ name: 'style', type: { kind: 'primitive', name: 'UIBlurEffectStyle' } }],
            },
          ],
        },
        {
          name: 'UIVisualEffectView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIVisualEffectView' } }],
          properties: [
            { name: 'effect', type: { kind: 'class', name: 'UIKit.UIBlurEffect', nullable: true } },
            { name: 'contentView', type: { kind: 'class', name: 'UIKit.UIView' }, readonly: true },
          ],
        },
        {
          name: 'UISwitch',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UISwitch' } }],
          properties: [
            { name: 'on', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'onTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'thumbTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
          ],
          methods: [
            {
              name: 'setOn',
              selector: 'setOn:animated:',
              returns: voidType,
              parameters: [
                { name: 'on', type: { kind: 'primitive', name: 'boolean' } },
                { name: 'animated', type: { kind: 'primitive', name: 'boolean' } },
              ],
            },
          ],
        },
        {
          name: 'UIProgressView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UIProgressView' } }],
          properties: [
            { name: 'progress', type: numberType },
            { name: 'progressTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'trackTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
          ],
        },
        {
          name: 'UISlider',
          extends: 'UIKit.UIControl',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'UIKit.UISlider' } }],
          properties: [
            { name: 'value', type: numberType },
            { name: 'minimumValue', type: numberType },
            { name: 'maximumValue', type: numberType },
            { name: 'continuous', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'minimumTrackTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'maximumTrackTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
            { name: 'thumbTintColor', type: { kind: 'class', name: 'UIKit.UIColor', nullable: true } },
          ],
        },
      ],
      functions: [
        {
          name: 'installRootView',
          returns: voidType,
          parameters: [{ name: 'view', type: { kind: 'class', name: 'UIKit.UIView' } }],
        },
      ],
    },
    {
      name: 'CoreLocation',
      imports: {
        Foundation: ['NSObject'],
      },
      constants: [
        { name: 'kCLLocationAccuracyBest', type: numberType, value: -1 },
        { name: 'CLDistanceFilterNone', type: numberType, value: -1 },
        { name: 'CLAuthorizationStatusNotDetermined', type: numberType, value: 0 },
        { name: 'CLAuthorizationStatusAuthorizedWhenInUse', type: numberType, value: 4 },
      ],
      functions: [
        {
          name: 'CLLocationCoordinate2DMake',
          returns: { kind: 'struct', name: 'CoreLocation.CLLocationCoordinate2D' },
          parameters: [
            { name: 'latitude', type: numberType },
            { name: 'longitude', type: numberType },
          ],
        },
      ],
      structs: [
        {
          name: 'CLLocationCoordinate2D',
          fields: [
            { name: 'latitude', type: numberType },
            { name: 'longitude', type: numberType },
          ],
        },
      ],
      classes: [
        {
          name: 'CLLocation',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'coordinate', type: { kind: 'struct', name: 'CoreLocation.CLLocationCoordinate2D' }, readonly: true },
            { name: 'horizontalAccuracy', type: numberType, readonly: true },
          ],
        },
        {
          name: 'CLLocationManager',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'CoreLocation.CLLocationManager' } }],
          properties: [
            { name: 'desiredAccuracy', type: numberType },
            { name: 'distanceFilter', type: numberType },
            { name: 'location', type: { kind: 'class', name: 'CoreLocation.CLLocation', nullable: true }, readonly: true },
          ],
          methods: [
            { name: 'requestWhenInUseAuthorization', selector: 'requestWhenInUseAuthorization', returns: voidType },
            { name: 'startUpdatingLocation', selector: 'startUpdatingLocation', returns: voidType },
            { name: 'stopUpdatingLocation', selector: 'stopUpdatingLocation', returns: voidType },
          ],
        },
      ],
    },
    {
      name: 'MapKit',
      imports: {
        CoreLocation: ['CLLocationCoordinate2D'],
        UIKit: ['UIView'],
      },
      constants: [
        { name: 'MKMapTypeStandard', type: mapTypeType, value: 0 },
        { name: 'MKMapTypeMutedStandard', type: mapTypeType, value: 1 },
        { name: 'MKMapTypeSatellite', type: mapTypeType, value: 2 },
        { name: 'MKUserTrackingModeNone', type: userTrackingModeType, value: 0 },
        { name: 'MKUserTrackingModeFollow', type: userTrackingModeType, value: 1 },
      ],
      functions: [
        {
          name: 'MKCoordinateRegionMakeWithDistance',
          returns: { kind: 'struct', name: 'MapKit.MKCoordinateRegion' },
          parameters: [
            { name: 'centerCoordinate', type: { kind: 'struct', name: 'CoreLocation.CLLocationCoordinate2D' } },
            { name: 'latitudinalMeters', type: numberType },
            { name: 'longitudinalMeters', type: numberType },
          ],
        },
      ],
      structs: [
        {
          name: 'MKCoordinateSpan',
          fields: [
            { name: 'latitudeDelta', type: numberType },
            { name: 'longitudeDelta', type: numberType },
          ],
        },
        {
          name: 'MKCoordinateRegion',
          fields: [
            { name: 'center', type: { kind: 'struct', name: 'CoreLocation.CLLocationCoordinate2D' } },
            { name: 'span', type: { kind: 'struct', name: 'MapKit.MKCoordinateSpan' } },
          ],
        },
      ],
      classes: [
        {
          name: 'MKMapView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'MapKit.MKMapView' } }],
          properties: [
            { name: 'mapType', type: mapTypeType },
            { name: 'showsUserLocation', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'userTrackingMode', type: userTrackingModeType },
          ],
          methods: [
            {
              name: 'setRegionAnimated',
              selector: 'setRegion:animated:',
              returns: voidType,
              parameters: [
                { name: 'region', type: { kind: 'struct', name: 'MapKit.MKCoordinateRegion' } },
                { name: 'animated', type: { kind: 'primitive', name: 'boolean' } },
              ],
            },
          ],
        },
      ],
    },
    {
      name: 'CoreMedia',
      functions: [
        {
          name: 'CMTimeMakeWithSeconds',
          returns: { kind: 'struct', name: 'CoreMedia.CMTime' },
          parameters: [
            { name: 'seconds', type: numberType },
            { name: 'preferredTimescale', type: numberType },
          ],
        },
      ],
      structs: [
        {
          name: 'CMTime',
          fields: [
            { name: 'value', type: numberType },
            { name: 'timescale', type: numberType },
            { name: 'flags', type: numberType },
            { name: 'epoch', type: numberType },
          ],
        },
      ],
    },
    {
      name: 'AVFoundation',
      imports: {
        CoreGraphics: ['CGRect', 'CGPoint'],
        CoreMedia: ['CMTime'],
        Foundation: ['NSData', 'NSObject'],
        QuartzCore: ['CALayer'],
      },
      constants: [
        { name: 'AVMediaTypeVideo', type: stringType, value: 'vide' },
        { name: 'AVLayerVideoGravityResizeAspectFill', type: stringType, value: 'resizeAspectFill' },
        { name: 'AVCaptureSessionPresetPhoto', type: stringType, value: 'Photo' },
        { name: 'AVCaptureSessionPresetHigh', type: stringType, value: 'High' },
        { name: 'AVCaptureSessionPresetMedium', type: stringType, value: 'Medium' },
        { name: 'AVCaptureFocusModeLocked', type: captureFocusModeType, value: 0 },
        { name: 'AVCaptureFocusModeAutoFocus', type: captureFocusModeType, value: 1 },
        { name: 'AVCaptureFocusModeContinuousAutoFocus', type: captureFocusModeType, value: 2 },
        { name: 'AVCaptureExposureModeLocked', type: captureExposureModeType, value: 0 },
        { name: 'AVCaptureExposureModeAutoExpose', type: captureExposureModeType, value: 1 },
        { name: 'AVCaptureExposureModeContinuousAutoExposure', type: captureExposureModeType, value: 2 },
        { name: 'AVCaptureExposureModeCustom', type: captureExposureModeType, value: 3 },
        { name: 'AVCaptureWhiteBalanceModeLocked', type: captureWhiteBalanceModeType, value: 0 },
        { name: 'AVCaptureWhiteBalanceModeAutoWhiteBalance', type: captureWhiteBalanceModeType, value: 1 },
        { name: 'AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance', type: captureWhiteBalanceModeType, value: 2 },
        { name: 'AVCaptureFlashModeOff', type: captureFlashModeType, value: 0 },
        { name: 'AVCaptureFlashModeOn', type: captureFlashModeType, value: 1 },
        { name: 'AVCaptureFlashModeAuto', type: captureFlashModeType, value: 2 },
        { name: 'AVCapturePhotoQualityPrioritizationSpeed', type: capturePhotoQualityPrioritizationType, value: 1 },
        { name: 'AVCapturePhotoQualityPrioritizationBalanced', type: capturePhotoQualityPrioritizationType, value: 2 },
        { name: 'AVCapturePhotoQualityPrioritizationQuality', type: capturePhotoQualityPrioritizationType, value: 3 },
        { name: 'AVCaptureDevicePositionUnspecified', type: captureDevicePositionType, value: 0 },
        { name: 'AVCaptureDevicePositionBack', type: captureDevicePositionType, value: 1 },
        { name: 'AVCaptureDevicePositionFront', type: captureDevicePositionType, value: 2 },
        { name: 'AVCaptureDeviceTypeBuiltInWideAngleCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInWideAngleCamera' },
        { name: 'AVCaptureDeviceTypeBuiltInUltraWideCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInUltraWideCamera' },
        { name: 'AVCaptureDeviceTypeBuiltInTelephotoCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInTelephotoCamera' },
        { name: 'AVCaptureDeviceTypeBuiltInDualCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInDualCamera' },
        { name: 'AVCaptureDeviceTypeBuiltInDualWideCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInDualWideCamera' },
        { name: 'AVCaptureDeviceTypeBuiltInTripleCamera', type: stringType, value: 'AVCaptureDeviceTypeBuiltInTripleCamera' },
      ],
      classes: [
        {
          name: 'AVCaptureInput',
          extends: 'Foundation.NSObject',
        },
        {
          name: 'AVCaptureOutput',
          extends: 'Foundation.NSObject',
        },
        {
          name: 'AVCaptureDeviceFormat',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'minISO', type: numberType, readonly: true },
            { name: 'maxISO', type: numberType, readonly: true },
            { name: 'videoMaxZoomFactor', type: numberType, readonly: true },
          ],
        },
        {
          name: 'AVCaptureDevice',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'activeFormat', type: { kind: 'class', name: 'AVFoundation.AVCaptureDeviceFormat' }, readonly: true },
            { name: 'videoZoomFactor', type: numberType },
            { name: 'minAvailableVideoZoomFactor', type: numberType, readonly: true },
            { name: 'maxAvailableVideoZoomFactor', type: numberType, readonly: true },
            { name: 'focusPointOfInterest', type: { kind: 'struct', name: 'CoreGraphics.CGPoint' } },
            { name: 'focusMode', type: captureFocusModeType },
            { name: 'isFocusPointOfInterestSupported', type: { kind: 'primitive', name: 'boolean' }, readonly: true },
            { name: 'exposurePointOfInterest', type: { kind: 'struct', name: 'CoreGraphics.CGPoint' } },
            { name: 'exposureMode', type: captureExposureModeType },
            { name: 'isExposurePointOfInterestSupported', type: { kind: 'primitive', name: 'boolean' }, readonly: true },
            { name: 'exposureTargetBias', type: numberType, readonly: true },
            { name: 'minExposureTargetBias', type: numberType, readonly: true },
            { name: 'maxExposureTargetBias', type: numberType, readonly: true },
            { name: 'ISO', type: numberType, readonly: true },
            { name: 'whiteBalanceMode', type: captureWhiteBalanceModeType },
            { name: 'hasFlash', type: { kind: 'primitive', name: 'boolean' }, readonly: true },
            { name: 'virtualDeviceSwitchOverVideoZoomFactors', type: numberArrayType, readonly: true },
          ],
          methods: [
            {
              name: 'defaultDeviceWithMediaType',
              selector: 'defaultDeviceWithMediaType:',
              static: true,
              returns: { kind: 'class', name: 'AVFoundation.AVCaptureDevice', nullable: true },
              parameters: [{ name: 'mediaType', type: stringType }],
            },
            {
              name: 'defaultDeviceWithDeviceTypeMediaTypePosition',
              selector: 'defaultDeviceWithDeviceType:mediaType:position:',
              static: true,
              returns: { kind: 'class', name: 'AVFoundation.AVCaptureDevice', nullable: true },
              parameters: [
                { name: 'deviceType', type: stringType },
                { name: 'mediaType', type: stringType },
                { name: 'position', type: captureDevicePositionType },
              ],
            },
            {
              name: 'lockForConfiguration',
              selector: 'lockForConfiguration:',
              returns: { kind: 'primitive', name: 'boolean' },
            },
            { name: 'unlockForConfiguration', selector: 'unlockForConfiguration', returns: voidType },
            {
              name: 'isFocusModeSupported',
              selector: 'isFocusModeSupported:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'focusMode', type: captureFocusModeType }],
            },
            {
              name: 'isExposureModeSupported',
              selector: 'isExposureModeSupported:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'exposureMode', type: captureExposureModeType }],
            },
            {
              name: 'isWhiteBalanceModeSupported',
              selector: 'isWhiteBalanceModeSupported:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'whiteBalanceMode', type: captureWhiteBalanceModeType }],
            },
            {
              name: 'isFlashModeSupported',
              selector: 'isFlashModeSupported:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'flashMode', type: captureFlashModeType }],
            },
            {
              name: 'setExposureTargetBiasCompletionHandler',
              selector: 'setExposureTargetBias:completionHandler:',
              returns: voidType,
              parameters: [
                { name: 'bias', type: numberType },
                { name: 'handler', type: cmtimeCallbackType },
              ],
            },
            {
              name: 'setExposureModeCustomWithDurationISOCompletionHandler',
              selector: 'setExposureModeCustomWithDuration:ISO:completionHandler:',
              returns: voidType,
              parameters: [
                { name: 'duration', type: { kind: 'struct', name: 'CoreMedia.CMTime' } },
                { name: 'ISO', type: numberType },
                { name: 'handler', type: cmtimeCallbackType },
              ],
            },
          ],
        },
        {
          name: 'AVCaptureDeviceInput',
          extends: 'AVFoundation.AVCaptureInput',
          methods: [
            {
              name: 'deviceInputWithDevice',
              selector: 'deviceInputWithDevice:error:',
              static: true,
              returns: { kind: 'class', name: 'AVFoundation.AVCaptureDeviceInput', nullable: true },
              parameters: [{ name: 'device', type: { kind: 'class', name: 'AVFoundation.AVCaptureDevice' } }],
            },
          ],
        },
        {
          name: 'AVCaptureSession',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AVFoundation.AVCaptureSession' } }],
          properties: [{ name: 'sessionPreset', type: stringType }],
          methods: [
            { name: 'beginConfiguration', selector: 'beginConfiguration', returns: voidType },
            { name: 'commitConfiguration', selector: 'commitConfiguration', returns: voidType },
            {
              name: 'canAddInput',
              selector: 'canAddInput:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'input', type: { kind: 'class', name: 'AVFoundation.AVCaptureInput' } }],
            },
            {
              name: 'canSetSessionPreset',
              selector: 'canSetSessionPreset:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'preset', type: stringType }],
            },
            {
              name: 'addInput',
              selector: 'addInput:',
              returns: voidType,
              parameters: [{ name: 'input', type: { kind: 'class', name: 'AVFoundation.AVCaptureInput' } }],
            },
            {
              name: 'canAddOutput',
              selector: 'canAddOutput:',
              returns: { kind: 'primitive', name: 'boolean' },
              parameters: [{ name: 'output', type: { kind: 'class', name: 'AVFoundation.AVCaptureOutput' } }],
            },
            {
              name: 'addOutput',
              selector: 'addOutput:',
              returns: voidType,
              parameters: [{ name: 'output', type: { kind: 'class', name: 'AVFoundation.AVCaptureOutput' } }],
            },
            { name: 'startRunning', selector: 'startRunning', returns: voidType },
            { name: 'stopRunning', selector: 'stopRunning', returns: voidType },
          ],
        },
        {
          name: 'AVCapturePhotoSettings',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'flashMode', type: captureFlashModeType },
            { name: 'photoQualityPrioritization', type: capturePhotoQualityPrioritizationType },
          ],
          methods: [
            {
              name: 'photoSettings',
              selector: 'photoSettings',
              static: true,
              returns: { kind: 'class', name: 'AVFoundation.AVCapturePhotoSettings' },
            },
          ],
        },
        {
          name: 'AVCapturePhotoOutput',
          extends: 'AVFoundation.AVCaptureOutput',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AVFoundation.AVCapturePhotoOutput' } }],
          properties: [
            { name: 'maxPhotoQualityPrioritization', type: capturePhotoQualityPrioritizationType },
          ],
          methods: [
            {
              name: 'capturePhotoWithSettingsHandler',
              selector: 'capturePhotoWithSettings:handler:',
              returns: voidType,
              parameters: [
                { name: 'settings', type: { kind: 'class', name: 'AVFoundation.AVCapturePhotoSettings' } },
                { name: 'handler', type: photoCaptureHandlerType },
              ],
            },
          ],
        },
        {
          name: 'AVCaptureVideoPreviewLayer',
          extends: 'QuartzCore.CALayer',
          properties: [
            { name: 'videoGravity', type: stringType },
          ],
          methods: [
            {
              name: 'layerWithSession',
              selector: 'layerWithSession:',
              static: true,
              returns: { kind: 'class', name: 'AVFoundation.AVCaptureVideoPreviewLayer' },
              parameters: [{ name: 'session', type: { kind: 'class', name: 'AVFoundation.AVCaptureSession' } }],
            },
          ],
        },
      ],
    },
    {
      name: 'Metal',
      constants: [
        { name: 'MTLPixelFormatInvalid', type: metalPixelFormatType, value: 0 },
        { name: 'MTLPixelFormatBGRA8Unorm_sRGB', type: metalPixelFormatType, value: 80 },
        { name: 'MTLPixelFormatDepth32Float', type: metalPixelFormatType, value: 252 },
        { name: 'MTLPrimitiveTypeTriangle', type: metalPrimitiveType, value: 3 },
        { name: 'MTLResourceStorageModeShared', type: metalResourceOptionsType, value: 0 },
        { name: 'MTLCompareFunctionLess', type: metalCompareFunctionType, value: 2 },
      ],
      functions: [
        {
          name: 'MTLCreateSystemDefaultDevice',
          returns: { kind: 'class', name: 'Metal.MTLDevice', nullable: true },
        },
        {
          name: 'MTLClearColorMake',
          returns: { kind: 'struct', name: 'Metal.MTLClearColor' },
          parameters: [
            { name: 'red', type: numberType },
            { name: 'green', type: numberType },
            { name: 'blue', type: numberType },
            { name: 'alpha', type: numberType },
          ],
        },
      ],
      structs: [
        {
          name: 'MTLClearColor',
          fields: [
            { name: 'red', type: numberType },
            { name: 'green', type: numberType },
            { name: 'blue', type: numberType },
            { name: 'alpha', type: numberType },
          ],
        },
      ],
      classes: [
        {
          name: 'MTLCompileOptions',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'Metal.MTLCompileOptions' } }],
        },
        {
          name: 'MTLDevice',
          methods: [
            {
              name: 'newCommandQueue',
              selector: 'newCommandQueue',
              returns: { kind: 'class', name: 'Metal.MTLCommandQueue', nullable: true },
            },
            {
              name: 'newLibraryWithSourceOptionsError',
              selector: 'newLibraryWithSource:options:error:',
              returns: { kind: 'class', name: 'Metal.MTLLibrary', nullable: true },
              parameters: [
                { name: 'source', type: stringType },
                { name: 'options', type: { kind: 'class', name: 'Metal.MTLCompileOptions' } },
              ],
            },
            {
              name: 'newBufferWithBytesLengthOptions',
              selector: 'newBufferWithBytes:length:options:',
              returns: { kind: 'class', name: 'Metal.MTLBuffer', nullable: true },
              parameters: [
                { name: 'bytes', type: numberArrayType },
                { name: 'length', type: numberType },
                { name: 'options', type: metalResourceOptionsType },
              ],
            },
            {
              name: 'newRenderPipelineStateWithDescriptorError',
              selector: 'newRenderPipelineStateWithDescriptor:error:',
              returns: { kind: 'class', name: 'Metal.MTLRenderPipelineState', nullable: true },
              parameters: [{ name: 'descriptor', type: { kind: 'class', name: 'Metal.MTLRenderPipelineDescriptor' } }],
            },
            {
              name: 'newDepthStencilStateWithDescriptor',
              selector: 'newDepthStencilStateWithDescriptor:',
              returns: { kind: 'class', name: 'Metal.MTLDepthStencilState', nullable: true },
              parameters: [{ name: 'descriptor', type: { kind: 'class', name: 'Metal.MTLDepthStencilDescriptor' } }],
            },
          ],
        },
        {
          name: 'MTLCommandQueue',
          methods: [
            {
              name: 'commandBuffer',
              selector: 'commandBuffer',
              returns: { kind: 'class', name: 'Metal.MTLCommandBuffer', nullable: true },
            },
          ],
        },
        {
          name: 'MTLCommandBuffer',
          methods: [
            {
              name: 'renderCommandEncoderWithDescriptor',
              selector: 'renderCommandEncoderWithDescriptor:',
              returns: { kind: 'class', name: 'Metal.MTLRenderCommandEncoder', nullable: true },
              parameters: [{ name: 'descriptor', type: { kind: 'class', name: 'Metal.MTLRenderPassDescriptor' } }],
            },
            {
              name: 'presentDrawable',
              selector: 'presentDrawable:',
              returns: voidType,
              parameters: [{ name: 'drawable', type: { kind: 'class', name: 'Metal.MTLDrawable' } }],
            },
            { name: 'commit', selector: 'commit', returns: voidType },
          ],
        },
        {
          name: 'MTLLibrary',
          methods: [
            {
              name: 'newFunctionWithName',
              selector: 'newFunctionWithName:',
              returns: { kind: 'class', name: 'Metal.MTLFunction', nullable: true },
              parameters: [{ name: 'name', type: stringType }],
            },
          ],
        },
        { name: 'MTLFunction' },
        {
          name: 'MTLRenderPipelineDescriptor',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'Metal.MTLRenderPipelineDescriptor' } }],
          properties: [
            { name: 'vertexFunction', type: { kind: 'class', name: 'Metal.MTLFunction', nullable: true } },
            { name: 'fragmentFunction', type: { kind: 'class', name: 'Metal.MTLFunction', nullable: true } },
            { name: 'colorAttachments', type: { kind: 'class', name: 'Metal.MTLRenderPipelineColorAttachmentDescriptorArray' }, readonly: true },
            { name: 'depthAttachmentPixelFormat', type: metalPixelFormatType },
          ],
        },
        {
          name: 'MTLRenderPipelineColorAttachmentDescriptorArray',
          methods: [
            {
              name: 'objectAtIndexedSubscript',
              selector: 'objectAtIndexedSubscript:',
              returns: { kind: 'class', name: 'Metal.MTLRenderPipelineColorAttachmentDescriptor' },
              parameters: [{ name: 'index', type: numberType }],
            },
          ],
        },
        {
          name: 'MTLRenderPipelineColorAttachmentDescriptor',
          properties: [{ name: 'pixelFormat', type: metalPixelFormatType }],
        },
        { name: 'MTLRenderPipelineState' },
        { name: 'MTLBuffer' },
        {
          name: 'MTLDepthStencilDescriptor',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'Metal.MTLDepthStencilDescriptor' } }],
          properties: [
            { name: 'depthCompareFunction', type: metalCompareFunctionType },
            { name: 'depthWriteEnabled', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        { name: 'MTLDepthStencilState' },
        {
          name: 'MTLRenderCommandEncoder',
          methods: [
            {
              name: 'setRenderPipelineState',
              selector: 'setRenderPipelineState:',
              returns: voidType,
              parameters: [{ name: 'pipelineState', type: { kind: 'class', name: 'Metal.MTLRenderPipelineState' } }],
            },
            {
              name: 'setDepthStencilState',
              selector: 'setDepthStencilState:',
              returns: voidType,
              parameters: [{ name: 'depthStencilState', type: { kind: 'class', name: 'Metal.MTLDepthStencilState' } }],
            },
            {
              name: 'setVertexBufferOffsetAtIndex',
              selector: 'setVertexBuffer:offset:atIndex:',
              returns: voidType,
              parameters: [
                { name: 'buffer', type: { kind: 'class', name: 'Metal.MTLBuffer' } },
                { name: 'offset', type: numberType },
                { name: 'index', type: numberType },
              ],
            },
            {
              name: 'setVertexBytesLengthAtIndex',
              selector: 'setVertexBytes:length:atIndex:',
              returns: voidType,
              parameters: [
                { name: 'bytes', type: numberArrayType },
                { name: 'length', type: numberType },
                { name: 'index', type: numberType },
              ],
            },
            {
              name: 'drawPrimitivesVertexStartVertexCount',
              selector: 'drawPrimitives:vertexStart:vertexCount:',
              returns: voidType,
              parameters: [
                { name: 'primitiveType', type: metalPrimitiveType },
                { name: 'vertexStart', type: numberType },
                { name: 'vertexCount', type: numberType },
              ],
            },
            { name: 'endEncoding', selector: 'endEncoding', returns: voidType },
          ],
        },
        { name: 'MTLRenderPassDescriptor' },
        { name: 'MTLDrawable' },
      ],
    },
    {
      name: 'MetalKit',
      imports: {
        CoreGraphics: ['CGSize'],
        Metal: ['MTLDevice', 'MTLDrawable', 'MTLClearColor', 'MTLRenderPassDescriptor'],
        UIKit: ['UIView'],
      },
      classes: [
        {
          name: 'MTKView',
          extends: 'UIKit.UIView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'MetalKit.MTKView' } }],
          properties: [
            { name: 'device', type: { kind: 'class', name: 'Metal.MTLDevice', nullable: true } },
            { name: 'delegate', type: { kind: 'class', name: 'MetalKit.MTKViewDelegate', nullable: true } },
            { name: 'colorPixelFormat', type: metalPixelFormatType },
            { name: 'depthStencilPixelFormat', type: metalPixelFormatType },
            { name: 'clearColor', type: { kind: 'struct', name: 'Metal.MTLClearColor' } },
            { name: 'preferredFramesPerSecond', type: numberType },
            { name: 'enableSetNeedsDisplay', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'paused', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'drawableSize', type: { kind: 'struct', name: 'CoreGraphics.CGSize' }, readonly: true },
            { name: 'currentRenderPassDescriptor', type: { kind: 'class', name: 'Metal.MTLRenderPassDescriptor', nullable: true }, readonly: true },
            { name: 'currentDrawable', type: { kind: 'class', name: 'Metal.MTLDrawable', nullable: true }, readonly: true },
          ],
        },
        {
          name: 'MTKViewDelegate',
          methods: [
            {
              name: 'create',
              selector: 'create:',
              static: true,
              returns: { kind: 'class', name: 'MetalKit.MTKViewDelegate' },
              parameters: [{ name: 'drawInMTKView', type: mtkViewDrawCallbackType }],
            },
          ],
        },
      ],
    },
    {
      name: 'Photos',
      imports: {
        Foundation: ['NSData', 'NSObject'],
      },
      classes: [
        {
          name: 'PHPhotoLibrary',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'saveImageData',
              selector: 'saveImageData:handler:',
              static: true,
              returns: voidType,
              parameters: [
                { name: 'data', type: { kind: 'class', name: 'Foundation.NSData' } },
                { name: 'handler', type: photoLibrarySaveHandlerType },
              ],
            },
          ],
        },
      ],
    },
    {
      name: 'AppKit',
      imports: {
        Foundation: ['NSObject'],
        CoreGraphics: ['CGRect'],
        QuartzCore: ['CALayer'],
      },
      constants: [
        // NSView.autoresizingMask
        { name: 'NSViewNotSizable', type: numberType, value: 0 },
        { name: 'NSViewWidthSizable', type: numberType, value: 2 },
        { name: 'NSViewHeightSizable', type: numberType, value: 16 },
        { name: 'NSViewMinXMargin', type: numberType, value: 1 },
        { name: 'NSViewMaxXMargin', type: numberType, value: 4 },
        { name: 'NSViewMinYMargin', type: numberType, value: 8 },
        { name: 'NSViewMaxYMargin', type: numberType, value: 32 },
        // NSVisualEffectView
        { name: 'NSVisualEffectMaterialSidebar', type: numberType, value: 7 },
        { name: 'NSVisualEffectMaterialHeaderView', type: numberType, value: 10 },
        { name: 'NSVisualEffectMaterialContentBackground', type: numberType, value: 18 },
        { name: 'NSVisualEffectMaterialUnderWindowBackground', type: numberType, value: 21 },
        { name: 'NSVisualEffectBlendingModeBehindWindow', type: numberType, value: 0 },
        { name: 'NSVisualEffectBlendingModeWithinWindow', type: numberType, value: 1 },
        { name: 'NSVisualEffectStateFollowsWindowActiveState', type: numberType, value: 0 },
        { name: 'NSVisualEffectStateActive', type: numberType, value: 1 },
        { name: 'NSVisualEffectStateInactive', type: numberType, value: 2 },
        // NSSplitView
        { name: 'NSSplitViewDividerStyleThick', type: numberType, value: 1 },
        { name: 'NSSplitViewDividerStyleThin', type: numberType, value: 2 },
        { name: 'NSSplitViewDividerStylePaneSplitter', type: numberType, value: 3 },
        // NSTextAlignment
        { name: 'NSTextAlignmentLeft', type: numberType, value: 0 },
        { name: 'NSTextAlignmentRight', type: numberType, value: 1 },
        { name: 'NSTextAlignmentCenter', type: numberType, value: 2 },
        // NSLineBreakMode
        { name: 'NSLineBreakByWordWrapping', type: numberType, value: 0 },
        { name: 'NSLineBreakByTruncatingTail', type: numberType, value: 4 },
        // NSUserInterfaceLayoutOrientation (NSStackView.orientation)
        { name: 'NSUserInterfaceLayoutOrientationHorizontal', type: numberType, value: 0 },
        { name: 'NSUserInterfaceLayoutOrientationVertical', type: numberType, value: 1 },
        // NSStackViewDistribution
        { name: 'NSStackViewDistributionFill', type: numberType, value: 0 },
        { name: 'NSStackViewDistributionFillEqually', type: numberType, value: 1 },
        { name: 'NSStackViewDistributionFillProportionally', type: numberType, value: 2 },
        { name: 'NSStackViewDistributionEqualSpacing', type: numberType, value: 3 },
        { name: 'NSStackViewDistributionEqualCentering', type: numberType, value: 4 },
        { name: 'NSStackViewDistributionGravityAreas', type: numberType, value: -1 },
        // NSLayoutConstraint.Attribute (NSStackView.alignment)
        { name: 'NSLayoutAttributeLeft', type: numberType, value: 1 },
        { name: 'NSLayoutAttributeRight', type: numberType, value: 2 },
        { name: 'NSLayoutAttributeTop', type: numberType, value: 3 },
        { name: 'NSLayoutAttributeBottom', type: numberType, value: 4 },
        { name: 'NSLayoutAttributeLeading', type: numberType, value: 5 },
        { name: 'NSLayoutAttributeTrailing', type: numberType, value: 6 },
        { name: 'NSLayoutAttributeWidth', type: numberType, value: 7 },
        { name: 'NSLayoutAttributeHeight', type: numberType, value: 8 },
        { name: 'NSLayoutAttributeCenterX', type: numberType, value: 9 },
        { name: 'NSLayoutAttributeCenterY', type: numberType, value: 10 },
        // NSLayoutConstraintOrientation (content hugging / compression resistance)
        { name: 'NSLayoutConstraintOrientationHorizontal', type: numberType, value: 0 },
        { name: 'NSLayoutConstraintOrientationVertical', type: numberType, value: 1 },
        // NSLayoutPriority
        { name: 'NSLayoutPriorityRequired', type: numberType, value: 1000 },
        { name: 'NSLayoutPriorityDefaultHigh', type: numberType, value: 750 },
        { name: 'NSLayoutPriorityDefaultLow', type: numberType, value: 250 },
        // NSBoxType (custom fill/border for rounded selection highlights)
        { name: 'NSBoxCustom', type: numberType, value: 4 },
        { name: 'ObjCTargetAction', type: selectorType, value: 'invoke:' },
      ],
      classes: [
        {
          name: 'NSColor',
          extends: 'Foundation.NSObject',
          methods: [
            { name: 'whiteColor', selector: 'whiteColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'blackColor', selector: 'blackColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'clearColor', selector: 'clearColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'labelColor', selector: 'labelColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'secondaryLabelColor', selector: 'secondaryLabelColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'tertiaryLabelColor', selector: 'tertiaryLabelColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'textColor', selector: 'textColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'controlBackgroundColor', selector: 'controlBackgroundColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'windowBackgroundColor', selector: 'windowBackgroundColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'separatorColor', selector: 'separatorColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'controlAccentColor', selector: 'controlAccentColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'systemBlueColor', selector: 'systemBlueColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            { name: 'systemYellowColor', selector: 'systemYellowColor', static: true, returns: { kind: 'class', name: 'AppKit.NSColor' } },
            {
              name: 'colorWithSRGBRedGreenBlueAlpha',
              selector: 'colorWithSRGBRed:green:blue:alpha:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSColor' },
              parameters: [
                { name: 'red', type: numberType },
                { name: 'green', type: numberType },
                { name: 'blue', type: numberType },
                { name: 'alpha', type: numberType },
              ],
            },
            {
              name: 'colorWithWhiteAlpha',
              selector: 'colorWithWhite:alpha:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSColor' },
              parameters: [
                { name: 'white', type: numberType },
                { name: 'alpha', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSLayoutConstraint',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'active', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        {
          name: 'NSLayoutXAxisAnchor',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'constraintEqualToAnchor',
              selector: 'constraintEqualToAnchor:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [{ name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' } }],
            },
            {
              name: 'constraintEqualToAnchorConstant',
              selector: 'constraintEqualToAnchor:constant:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [
                { name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' } },
                { name: 'constant', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSLayoutYAxisAnchor',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'constraintEqualToAnchor',
              selector: 'constraintEqualToAnchor:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [{ name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' } }],
            },
            {
              name: 'constraintEqualToAnchorConstant',
              selector: 'constraintEqualToAnchor:constant:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [
                { name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' } },
                { name: 'constant', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSLayoutDimension',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'constraintEqualToAnchor',
              selector: 'constraintEqualToAnchor:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [{ name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutDimension' } }],
            },
            {
              name: 'constraintEqualToConstant',
              selector: 'constraintEqualToConstant:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [{ name: 'constant', type: numberType }],
            },
            {
              name: 'constraintEqualToAnchorMultiplier',
              selector: 'constraintEqualToAnchor:multiplier:',
              returns: { kind: 'class', name: 'AppKit.NSLayoutConstraint' },
              parameters: [
                { name: 'anchor', type: { kind: 'class', name: 'AppKit.NSLayoutDimension' } },
                { name: 'multiplier', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSLayoutGuide',
          extends: 'Foundation.NSObject',
          properties: [
            { name: 'leadingAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' }, readonly: true },
            { name: 'trailingAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' }, readonly: true },
            { name: 'topAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' }, readonly: true },
            { name: 'bottomAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' }, readonly: true },
          ],
        },
        {
          name: 'ObjCTarget',
          methods: [
            {
              name: 'create',
              selector: 'create:',
              static: true,
              returns: { kind: 'class', name: 'Foundation.NSObject' },
              parameters: [{ name: 'callback', type: voidCallbackType }],
            },
          ],
        },
        {
          name: 'NSClickGestureRecognizer',
          extends: 'Foundation.NSObject',
          constructors: [
            {
              name: 'initWithTargetAction',
              selector: 'initWithTarget:action:',
              returns: { kind: 'class', name: 'AppKit.NSClickGestureRecognizer' },
              parameters: [
                { name: 'target', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } },
                { name: 'action', type: selectorType },
              ],
            },
          ],
          properties: [
            { name: 'numberOfClicksRequired', type: numberType },
          ],
        },
        {
          name: 'NSView',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSView' } }],
          properties: [
            { name: 'frame', type: { kind: 'struct', name: 'CoreGraphics.CGRect' } },
            { name: 'bounds', type: { kind: 'struct', name: 'CoreGraphics.CGRect' }, readonly: true },
            { name: 'wantsLayer', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'layer', type: { kind: 'class', name: 'QuartzCore.CALayer' }, readonly: true },
            { name: 'hidden', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'alphaValue', type: numberType },
            { name: 'autoresizingMask', type: numberType },
            { name: 'translatesAutoresizingMaskIntoConstraints', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'leadingAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' }, readonly: true },
            { name: 'trailingAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' }, readonly: true },
            { name: 'centerXAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutXAxisAnchor' }, readonly: true },
            { name: 'topAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' }, readonly: true },
            { name: 'bottomAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' }, readonly: true },
            { name: 'centerYAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutYAxisAnchor' }, readonly: true },
            { name: 'widthAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutDimension' }, readonly: true },
            { name: 'heightAnchor', type: { kind: 'class', name: 'AppKit.NSLayoutDimension' }, readonly: true },
            { name: 'safeAreaLayoutGuide', type: { kind: 'class', name: 'AppKit.NSLayoutGuide' }, readonly: true },
          ],
          methods: [
            {
              name: 'addSubview',
              selector: 'addSubview:',
              returns: voidType,
              parameters: [{ name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } }],
            },
            {
              name: 'addGestureRecognizer',
              selector: 'addGestureRecognizer:',
              returns: voidType,
              parameters: [{ name: 'recognizer', type: { kind: 'class', name: 'Foundation.NSObject' } }],
            },
            {
              name: 'setContentHuggingPriorityForOrientation',
              selector: 'setContentHuggingPriority:forOrientation:',
              returns: voidType,
              parameters: [
                { name: 'priority', type: numberType },
                { name: 'orientation', type: layoutConstraintOrientationType },
              ],
            },
            {
              name: 'setContentCompressionResistancePriorityForOrientation',
              selector: 'setContentCompressionResistancePriority:forOrientation:',
              returns: voidType,
              parameters: [
                { name: 'priority', type: numberType },
                { name: 'orientation', type: layoutConstraintOrientationType },
              ],
            },
          ],
        },
        {
          name: 'NSControl',
          extends: 'AppKit.NSView',
          properties: [
            { name: 'target', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } },
            { name: 'action', type: selectorType },
            { name: 'enabled', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        {
          name: 'NSBox',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSBox' } }],
          properties: [
            { name: 'boxType', type: numberType },
            { name: 'borderWidth', type: numberType },
            { name: 'cornerRadius', type: numberType },
            { name: 'fillColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'borderColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'titlePosition', type: numberType },
            { name: 'contentView', type: { kind: 'class', name: 'AppKit.NSView', nullable: true } },
          ],
        },
        {
          name: 'NSStackView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSStackView' } }],
          properties: [
            { name: 'orientation', type: numberType },
            { name: 'spacing', type: numberType },
            { name: 'alignment', type: numberType },
            { name: 'distribution', type: numberType },
            { name: 'detachesHiddenViews', type: { kind: 'primitive', name: 'boolean' } },
          ],
          methods: [
            {
              name: 'addArrangedSubview',
              selector: 'addArrangedSubview:',
              returns: voidType,
              parameters: [{ name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } }],
            },
            {
              name: 'insertArrangedSubviewAtIndex',
              selector: 'insertArrangedSubview:atIndex:',
              returns: voidType,
              parameters: [
                { name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } },
                { name: 'index', type: numberType },
              ],
            },
            {
              name: 'setHuggingPriorityForOrientation',
              selector: 'setHuggingPriority:forOrientation:',
              returns: voidType,
              parameters: [
                { name: 'priority', type: numberType },
                { name: 'orientation', type: layoutConstraintOrientationType },
              ],
            },
          ],
        },
        {
          name: 'NSTextField',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSTextField' } }],
          properties: [
            { name: 'stringValue', type: stringType },
            { name: 'placeholderString', type: { kind: 'primitive', name: 'string' } },
            { name: 'editable', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'selectable', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'bezeled', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'bordered', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'drawsBackground', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'backgroundColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'textColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'font', type: { kind: 'class', name: 'AppKit.NSFont', nullable: true } },
            { name: 'alignment', type: numberType },
            { name: 'lineBreakMode', type: numberType },
            { name: 'maximumNumberOfLines', type: numberType },
          ],
          methods: [
            {
              // Live edit notifications: the delegate receives controlTextDidChange:
              // on every keystroke (see ObjCTarget). A method (selector setDelegate:)
              // rather than a `delegate` property to avoid the member-name collision
              // with MTKView.delegate for dynamic receivers.
              name: 'attachTextDelegate',
              selector: 'setDelegate:',
              returns: voidType,
              parameters: [{ name: 'delegate', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } }],
            },
          ],
        },
        {
          name: 'NSFont',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'systemFontOfSize',
              selector: 'systemFontOfSize:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSFont' },
              parameters: [{ name: 'fontSize', type: numberType }],
            },
            {
              name: 'boldSystemFontOfSize',
              selector: 'boldSystemFontOfSize:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSFont' },
              parameters: [{ name: 'fontSize', type: numberType }],
            },
            {
              name: 'systemFontOfSizeWeight',
              selector: 'systemFontOfSize:weight:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSFont' },
              parameters: [
                { name: 'fontSize', type: numberType },
                { name: 'weight', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSVisualEffectView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSVisualEffectView' } }],
          properties: [
            { name: 'material', type: numberType },
            { name: 'blendingMode', type: numberType },
            { name: 'state', type: numberType },
            { name: 'emphasized', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        {
          name: 'NSScrollView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSScrollView' } }],
          properties: [
            { name: 'documentView', type: { kind: 'class', name: 'AppKit.NSView', nullable: true } },
            { name: 'hasVerticalScroller', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'hasHorizontalScroller', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'drawsBackground', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'automaticallyAdjustsContentInsets', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        {
          name: 'NSSplitView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSSplitView' } }],
          properties: [
            { name: 'vertical', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'dividerStyle', type: numberType },
          ],
          methods: [
            {
              name: 'addArrangedSubview',
              selector: 'addArrangedSubview:',
              returns: voidType,
              parameters: [{ name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } }],
            },
            { name: 'adjustSubviews', selector: 'adjustSubviews', returns: voidType },
            {
              name: 'setPositionOfDividerAtIndex',
              selector: 'setPosition:ofDividerAtIndex:',
              returns: voidType,
              parameters: [
                { name: 'position', type: numberType },
                { name: 'dividerIndex', type: numberType },
              ],
            },
          ],
        },
        {
          name: 'NSTextView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSTextView' } }],
          properties: [
            { name: 'string', type: stringType },
            { name: 'editable', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'selectable', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'drawsBackground', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'backgroundColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'textColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
            { name: 'font', type: { kind: 'class', name: 'AppKit.NSFont', nullable: true } },
          ],
          methods: [
            {
              // Live edit notifications: the delegate receives textDidChange: on
              // every keystroke (see ObjCTarget).
              name: 'attachTextDelegate',
              selector: 'setDelegate:',
              returns: voidType,
              parameters: [{ name: 'delegate', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } }],
            },
          ],
        },
        {
          name: 'NSImage',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'imageWithSystemSymbolNameAccessibilityDescription',
              selector: 'imageWithSystemSymbolName:accessibilityDescription:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSImage', nullable: true },
              parameters: [
                { name: 'symbolName', type: stringType },
                { name: 'accessibilityDescription', type: { kind: 'primitive', name: 'string' } },
              ],
            },
          ],
        },
        {
          name: 'NSImageView',
          extends: 'AppKit.NSView',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSImageView' } }],
          properties: [
            { name: 'image', type: { kind: 'class', name: 'AppKit.NSImage', nullable: true } },
            { name: 'contentTintColor', type: { kind: 'class', name: 'AppKit.NSColor', nullable: true } },
          ],
        },
        {
          name: 'NSButton',
          extends: 'AppKit.NSControl',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSButton' } }],
          properties: [
            { name: 'title', type: stringType },
            { name: 'bordered', type: { kind: 'primitive', name: 'boolean' } },
          ],
        },
        {
          name: 'NSViewController',
          extends: 'Foundation.NSObject',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSViewController' } }],
          properties: [
            { name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } },
            { name: 'title', type: { kind: 'primitive', name: 'string' } },
          ],
        },
        {
          name: 'NSSplitViewController',
          extends: 'AppKit.NSViewController',
          constructors: [{ name: 'init', selector: 'init', returns: { kind: 'class', name: 'AppKit.NSSplitViewController' } }],
          methods: [
            {
              name: 'addSplitViewItem',
              selector: 'addSplitViewItem:',
              returns: voidType,
              parameters: [{ name: 'item', type: { kind: 'class', name: 'AppKit.NSSplitViewItem' } }],
            },
          ],
        },
        {
          name: 'NSSplitViewItem',
          extends: 'Foundation.NSObject',
          methods: [
            {
              name: 'sidebarWithViewController',
              selector: 'sidebarWithViewController:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSSplitViewItem' },
              parameters: [{ name: 'viewController', type: { kind: 'class', name: 'AppKit.NSViewController' } }],
            },
            {
              name: 'contentListWithViewController',
              selector: 'contentListWithViewController:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSSplitViewItem' },
              parameters: [{ name: 'viewController', type: { kind: 'class', name: 'AppKit.NSViewController' } }],
            },
            {
              name: 'splitViewItemWithViewController',
              selector: 'splitViewItemWithViewController:',
              static: true,
              returns: { kind: 'class', name: 'AppKit.NSSplitViewItem' },
              parameters: [{ name: 'viewController', type: { kind: 'class', name: 'AppKit.NSViewController' } }],
            },
          ],
          properties: [
            { name: 'minimumThickness', type: numberType },
            { name: 'maximumThickness', type: numberType },
            { name: 'canCollapse', type: { kind: 'primitive', name: 'boolean' } },
            { name: 'preferredThicknessFraction', type: numberType },
          ],
        },
      ],
      functions: [
        {
          name: 'installRootView',
          returns: voidType,
          parameters: [{ name: 'view', type: { kind: 'class', name: 'AppKit.NSView' } }],
        },
        {
          name: 'installRootViewController',
          returns: voidType,
          parameters: [{ name: 'viewController', type: { kind: 'class', name: 'AppKit.NSViewController' } }],
        },
        {
          // Attach a real unified-title-bar NSToolbar to the window. `spec` is a
          // comma-separated list of items: an SF Symbol name renders a borderless
          // image button, `space` a flexible space, `search` a search field.
          name: 'installToolbar',
          returns: voidType,
          parameters: [
            { name: 'spec', type: stringType },
            // ObjCTarget invoked when the `square.and.pencil` (New Note) item is
            // clicked. Other items are decorative (enabled, bordered, no-op),
            // matching the reference.
            { name: 'newNoteTarget', type: { kind: 'class', name: 'Foundation.NSObject', nullable: true } },
          ],
        },
        {
          // Run a shell command (via /bin/bash -c) and return its combined
          // stdout+stderr as a string. A small native escape hatch (NSTask) for
          // companion apps that drive external tooling — e.g. the gea Companion
          // talking to the watch over USB through scripts/esp32-device-control.py.
          name: 'runDeviceCommand',
          returns: stringType,
          parameters: [{ name: 'command', type: stringType }],
        },
        {
          // Set `content` as the scroll view's document view inside a flipped
          // container, so a tall vertical list lays out top-down and the scroll
          // view opens at the top (instead of NSView's default bottom-left origin,
          // which makes the list open scrolled to the bottom/middle).
          name: 'setScrollDocumentTopAligned',
          returns: voidType,
          parameters: [
            { name: 'scrollView', type: { kind: 'class', name: 'AppKit.NSScrollView' } },
            { name: 'content', type: { kind: 'class', name: 'AppKit.NSView' } },
          ],
        },
      ],
    },
    {
      name: 'ActivityKit',
      classes: [
        {
          name: 'LiveActivityHandle',
          properties: [{ name: 'id', type: stringType, readonly: true }],
        },
      ],
      functions: [
        {
          name: 'requestLiveActivity',
          returns: { kind: 'class', name: 'ActivityKit.LiveActivityHandle' },
          parameters: [
            { name: 'attributesJSON', type: stringType },
            { name: 'contentStateJSON', type: stringType },
          ],
        },
        {
          name: 'updateLiveActivity',
          returns: voidType,
          parameters: [
            { name: 'activity', type: { kind: 'class', name: 'ActivityKit.LiveActivityHandle' } },
            { name: 'contentStateJSON', type: stringType },
          ],
        },
        {
          name: 'endLiveActivity',
          returns: voidType,
          parameters: [{ name: 'activity', type: { kind: 'class', name: 'ActivityKit.LiveActivityHandle' } }],
        },
      ],
    },
    {
      name: 'SwiftData',
      classes: [
        { name: 'ModelContainer' },
        { name: 'ModelContext' },
      ],
      functions: [
        {
          name: 'openModelContainer',
          returns: { kind: 'class', name: 'SwiftData.ModelContainer' },
          parameters: [{ name: 'schemaJSON', type: stringType }],
        },
        {
          name: 'mainModelContext',
          returns: { kind: 'class', name: 'SwiftData.ModelContext' },
          parameters: [{ name: 'container', type: { kind: 'class', name: 'SwiftData.ModelContainer' } }],
        },
        {
          name: 'insertModelJSON',
          returns: voidType,
          parameters: [
            { name: 'context', type: { kind: 'class', name: 'SwiftData.ModelContext' } },
            { name: 'modelJSON', type: stringType },
          ],
        },
        {
          name: 'saveModelContext',
          returns: voidType,
          parameters: [{ name: 'context', type: { kind: 'class', name: 'SwiftData.ModelContext' } }],
        },
        {
          name: 'fetchModelsJSON',
          returns: stringType,
          parameters: [
            { name: 'context', type: { kind: 'class', name: 'SwiftData.ModelContext' } },
            { name: 'descriptorJSON', type: stringType },
          ],
        },
      ],
    },
  ],
}

export function generateAppleDeclarations(sdk: AppleSdkDefinition): Record<string, string> {
  const declarations: Record<string, string> = {}
  for (const framework of sdk.frameworks) {
    declarations[`@geastack/apple/${framework.name}`] = declarationForFramework(framework)
  }
  return declarations
}

export function generateAppleRuntimeModules(sdk: AppleSdkDefinition): Record<string, string> {
  const modules: Record<string, string> = {}
  for (const framework of sdk.frameworks) {
    modules[`@geastack/apple/${framework.name}`] = runtimeModuleForFramework(framework)
  }
  return modules
}

export function generateAppleBridgeMetadata(sdk: AppleSdkDefinition): AppleBridgeMetadata {
  const metadata: AppleBridgeMetadata = {
    frameworks: sdk.frameworks.map((framework) => ({
      name: framework.name,
      ...(framework.bridgeHeaders?.length ? { bridgeHeaders: framework.bridgeHeaders } : {}),
    })),
    constants: {},
    functions: {},
    classes: {},
    structs: {},
  }
  for (const framework of sdk.frameworks) {
    for (const constant of framework.constants ?? []) {
      const key = qualifiedName(framework.name, constant.name)
      metadata.constants[key] = {
        framework: framework.name,
        name: constant.name,
        type: constant.type,
        value: constant.value,
      }
    }
    for (const fn of framework.functions ?? []) {
      const key = qualifiedName(framework.name, fn.name)
      metadata.functions[key] = functionMetadata(framework.name, fn)
    }
    for (const struct of framework.structs ?? []) {
      const key = qualifiedName(framework.name, struct.name)
      metadata.structs[key] = {
        framework: framework.name,
        name: struct.name,
        wrapper: cppTypeName(framework.name, struct.name),
        fields: struct.fields,
      }
    }
    for (const cls of framework.classes ?? []) {
      const key = qualifiedName(framework.name, cls.name)
      const constructor = cls.constructors?.[0]
      metadata.classes[key] = {
        framework: framework.name,
        name: cls.name,
        ...(cls.extends ? { extends: cls.extends } : {}),
        wrapper: cppTypeName(framework.name, cls.name),
        ...(constructor ? { constructor: { selector: constructor.selector, thunk: constructorThunk(framework.name, cls.name), parameters: constructor.parameters ?? [] } } : {}),
        methods: Object.fromEntries((cls.methods ?? []).map((method) => [method.name, methodMetadata(framework.name, cls.name, method)])),
        properties: Object.fromEntries((cls.properties ?? []).map((property) => [property.name, propertyMetadata(framework.name, cls.name, property)])),
      }
    }
  }
  return metadata
}

export function generateAppleNativeBridgeHeader(metadata: AppleBridgeMetadata): string {
  const lines = [
    '#pragma once',
    '',
    '#import <CoreGraphics/CoreGraphics.h>',
  ]
  const importedFrameworks = new Set<string>()
  for (const framework of metadata.frameworks) {
    if (objcFrameworkImports[framework.name]) importedFrameworks.add(framework.name)
  }
  for (const framework of [...importedFrameworks].sort()) {
    const header = objcFrameworkImports[framework]
    lines.push(`#if __has_include(<${header}>)`)
    lines.push(`#import <${header}>`)
    lines.push('#endif')
  }
  for (const framework of metadata.frameworks) {
    for (const header of framework.bridgeHeaders ?? []) {
      lines.push(`#if __has_include("${header}")`)
      lines.push(`#import "${header}"`)
      lines.push('#endif')
    }
  }
  lines.push(
    '',
    '#include <cstdint>',
    '#include <functional>',
    '#include <string>',
    '#include <vector>',
    '',
    '@class NSString;',
    'namespace gea::apple::Foundation {',
    'NSString *toNSString(const std::string &value);',
    'std::string fromNSString(NSString *value);',
    '}',
    '',
    'namespace gea::apple::objc {',
    'void *object(double handle);',
    'double retain(void *object);',
    'void release(double handle);',
    '}',
    '',
  )

  for (const framework of metadata.frameworks) {
    const structs = Object.values(metadata.structs).filter((entry) => entry.framework === framework.name)
    const classes = Object.values(metadata.classes).filter((entry) => entry.framework === framework.name)
    if (structs.length === 0 && classes.length === 0) continue

    lines.push(`namespace gea::apple::${framework.name} {`)
    for (const struct of structs) {
      if (nativeStructFrameworks.has(framework.name)) {
        lines.push(`using ${struct.name} = ::${struct.name};`, '')
      } else {
        lines.push(`struct ${struct.name} {`)
        for (const field of struct.fields) {
          lines.push(`  ${cppValueType(field.type, framework.name, { preferLocalNames: true })} ${field.name}${defaultInitializer(field.type)};`)
        }
        lines.push('};', '')
      }
    }
    for (const cls of classes) {
      const base = cls.extends ? ` : ${cppValueType({ kind: 'class', name: cls.extends }, framework.name)}` : ''
      lines.push(`struct ${cls.name}${base} {`)
      if (cls.extends) {
        const [, baseName] = splitQualifiedName(cls.extends, framework.name)
        lines.push(`  using ${cppValueType({ kind: 'class', name: cls.extends }, framework.name)}::${baseName};`)
      } else {
        lines.push('  double handle = 0;')
        lines.push(`  ${cls.name}() = default;`)
        lines.push(`  explicit ${cls.name}(double rawHandle) : handle(rawHandle) {}`)
      }
      lines.push('  explicit operator bool() const { return handle != 0; }')
      lines.push('};', '')
    }
    lines.push('}', '')
  }

  appendUIKitCallbackBridgeDeclarations(lines, metadata)
  appendBridgeDeclarations(lines, metadata)

  return `${lines.join('\n').trimEnd()}\n`
}

function appendBridgeDeclarations(lines: string[], metadata: AppleBridgeMetadata): void {
  const seen = new Set<string>()
  for (const block of sourceBackedBridgeDeclarations(metadata)) {
    const signature = block.join('\n')
    if (seen.has(signature)) continue
    seen.add(signature)
    lines.push(...block)
  }
  if (seen.size > 0) lines.push('')
}

function sourceBackedBridgeDeclarations(metadata: AppleBridgeMetadata): string[][] {
  const declarations: string[][] = []
  const append = (name: string, returnType: string, params: string) => {
    declarations.push(bridgeDeclaration(name, returnType, params))
  }
  for (const fn of Object.values(metadata.functions)) {
    if (fn.framework === 'Dispatch' || fn.framework === 'Metal') {
      append(fn.thunk, cppValueType(fn.returns, fn.framework), fn.parameters.map((parameter) => bridgeParameter(parameter, fn.framework)).join(', '))
    }
  }
  for (const cls of Object.values(metadata.classes)) {
    const constructor = Object.prototype.hasOwnProperty.call(cls, 'constructor') ? cls.constructor : undefined
    if (constructor && bridgeSourceDefinesConstructor(cls)) {
      append(constructor.thunk, 'double', (constructor.parameters ?? []).map((parameter) => bridgeParameter(parameter, cls.framework)).join(', '))
    }
    for (const method of Object.values(cls.methods)) {
      if (!bridgeSourceDefinesMethod(cls, method)) continue
      const parameters = method.static
        ? method.parameters
        : [{ name: 'self', type: { kind: 'class', name: `${cls.framework}.${cls.name}` } as AppleTypeReference }, ...method.parameters]
      append(method.thunk, cppValueType(method.returns, cls.framework), parameters.map((parameter) => bridgeParameter(parameter, cls.framework)).join(', '))
    }
    for (const property of Object.values(cls.properties)) {
      if (!bridgeSourceDefinesProperty(cls, property)) continue
      append(property.getter, cppValueType(property.type, cls.framework), `${cls.wrapper} self`)
      if (property.setter) append(property.setter, 'void', `${cls.wrapper} self, ${cppValueType(property.type, cls.framework)} value`)
    }
  }
  return declarations
}

function bridgeSourceDefinesConstructor(cls: AppleBridgeClassMetadata): boolean {
  return cls.framework === 'Metal' || cls.framework === 'MetalKit'
}

function bridgeSourceDefinesMethod(cls: AppleBridgeClassMetadata, method: AppleBridgeMethodMetadata): boolean {
  if (cls.framework === 'Metal' || cls.framework === 'MetalKit') return true
  if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDeviceInput' && method.name === 'deviceInputWithDevice') return true
  if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'lockForConfiguration') return true
  if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'setExposureTargetBiasCompletionHandler') return true
  if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'setExposureModeCustomWithDurationISOCompletionHandler') return true
  if (cls.framework === 'AVFoundation' && cls.name === 'AVCapturePhotoOutput' && method.name === 'capturePhotoWithSettingsHandler') return true
  return cls.framework === 'Photos' && cls.name === 'PHPhotoLibrary' && method.name === 'saveImageData'
}

function bridgeSourceDefinesProperty(cls: AppleBridgeClassMetadata, property: AppleBridgePropertyMetadata): boolean {
  if (cls.framework === 'Metal' || cls.framework === 'MetalKit') return true
  return cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && property.name === 'virtualDeviceSwitchOverVideoZoomFactors'
}

function bridgeParameter(parameter: AppleParameterDefinition, localFramework: string): string {
  return `${cppValueType(parameter.type, localFramework)} ${parameter.name}`
}

function bridgeDeclaration(name: string, returnType: string, params: string): string[] {
  const target = cppFunctionTarget(name)
  if (!target.namespaceName) return [`${returnType} ${target.bareName}(${params});`]
  return [`namespace ${target.namespaceName} {`, `${returnType} ${target.bareName}(${params});`, '}']
}

export function generateAppleNativeBridgeObjCxxSource(metadata: AppleBridgeMetadata): string {
  const importedFrameworks = new Set<string>()
  for (const framework of metadata.frameworks) {
    if (objcFrameworkImports[framework.name]) importedFrameworks.add(framework.name)
  }

  const lines = [
    '#include "gea/apple/native_bridge.h"',
    '',
    '#import <CoreGraphics/CoreGraphics.h>',
  ]
  for (const framework of [...importedFrameworks].sort()) {
    const header = objcFrameworkImports[framework]
    lines.push(`#if __has_include(<${header}>)`)
    lines.push(`#import <${header}>`)
    lines.push('#endif')
  }
  lines.push(
    '',
    '#include <cstdint>',
    '#include <functional>',
    '#include <mutex>',
    '#include <unordered_map>',
    '#include <utility>',
    '#include <vector>',
    '',
    'namespace {',
    'std::mutex geaAppleObjectMutex;',
    'std::unordered_map<std::uint64_t, void *> geaAppleObjects;',
    'std::uint64_t geaAppleNextObjectHandle = 1;',
    '}',
    '',
    'namespace gea::apple::objc {',
    'void *object(double handle) {',
    '  if (handle <= 0) return nullptr;',
    '  const auto key = static_cast<std::uint64_t>(handle);',
    '  std::lock_guard<std::mutex> lock(geaAppleObjectMutex);',
    '  const auto found = geaAppleObjects.find(key);',
    '  return found == geaAppleObjects.end() ? nullptr : found->second;',
    '}',
    '',
    'double retain(void *object) {',
    '  if (!object) return 0;',
    '  void *retained = const_cast<void *>(CFRetain(object));',
    '  std::lock_guard<std::mutex> lock(geaAppleObjectMutex);',
    '  const auto handle = geaAppleNextObjectHandle++;',
    '  geaAppleObjects.emplace(handle, retained);',
    '  return static_cast<double>(handle);',
    '}',
    '',
    'void release(double handle) {',
    '  if (handle <= 0) return;',
    '  void *object = nullptr;',
    '  {',
    '    std::lock_guard<std::mutex> lock(geaAppleObjectMutex);',
    '    const auto key = static_cast<std::uint64_t>(handle);',
    '    const auto found = geaAppleObjects.find(key);',
    '    if (found == geaAppleObjects.end()) return;',
    '    object = found->second;',
    '    geaAppleObjects.erase(found);',
    '  }',
    '  CFRelease(object);',
    '}',
    '}',
    '',
  )

  appendFoundationStringConversions(lines, metadata)
  appendDispatchBridges(lines, metadata)
  appendAVFoundationBridges(lines, metadata)
  appendPhotosBridges(lines, metadata)
  appendMetalBridges(lines, metadata)
  appendMetalKitBridges(lines, metadata)
  appendUIKitCallbackBridges(lines, metadata)

  return `${lines.join('\n').trimEnd()}\n`
}

function declarationForFramework(framework: AppleFrameworkDefinition): string {
  const lines: string[] = []
  for (const [module, imports] of Object.entries(framework.imports ?? {})) {
    lines.push(`import type { ${imports.join(', ')} } from '@geastack/apple/${module}'`)
  }
  if (lines.length > 0) lines.push('')
  if (frameworkUsesPrimitive(framework, 'selector')) {
    lines.push('export type Selector = string', '')
  }
  for (const constant of framework.constants ?? []) {
    lines.push(`export declare const ${constant.name}: ${typeScriptType(constant.type, framework.name)}`)
  }
  if ((framework.constants ?? []).length > 0) lines.push('')
  for (const fn of framework.functions ?? []) {
    lines.push(`export declare function ${fn.name}(${parametersSignature(fn.parameters ?? [], framework.name)}): ${typeScriptType(fn.returns, framework.name)}`)
  }
  if ((framework.functions ?? []).length > 0) lines.push('')
  for (const struct of framework.structs ?? []) {
    lines.push(`export interface ${struct.name} {`)
    for (const field of struct.fields) {
      lines.push(`  ${field.name}: ${typeScriptType(field.type, framework.name)}`)
    }
    lines.push('}', '')
  }
  for (const cls of framework.classes ?? []) {
    const base = cls.extends ? ` extends ${shortTypeName(cls.extends)}` : ''
    lines.push(`export declare class ${cls.name}${base} {`)
    for (const constructor of cls.constructors ?? []) {
      lines.push(`  constructor(${parametersSignature(constructor.parameters ?? [], framework.name)})`)
    }
    for (const property of cls.properties ?? []) {
      const readonly = property.readonly ? 'readonly ' : ''
      lines.push(`  ${readonly}${property.name}: ${typeScriptType(property.type, framework.name)}`)
    }
    for (const method of cls.methods ?? []) {
      const prefix = method.static ? 'static ' : ''
      lines.push(`  ${prefix}${method.name}(${parametersSignature(method.parameters ?? [], framework.name)}): ${typeScriptType(method.returns, framework.name)}`)
    }
    lines.push('}', '')
  }
  return `${lines.join('\n').trimEnd()}\n`
}

function runtimeModuleForFramework(framework: AppleFrameworkDefinition): string {
  if ((framework.constants ?? []).length === 0 && (framework.functions ?? []).length === 0 && (framework.classes ?? []).length === 0) {
    return 'export {}\n'
  }
  const nativeOnly = `geaApple${framework.name}NativeOnly`
  const lines = [
    `function ${nativeOnly}(name) {`,
    `  throw new Error(\`@geastack/apple/${framework.name} \${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.\`)`,
    `}`,
    '',
  ]
  for (const constant of framework.constants ?? []) {
    lines.push(`export const ${constant.name} = ${JSON.stringify(constant.value)}`)
  }
  if ((framework.constants ?? []).length > 0) lines.push('')
  for (const fn of framework.functions ?? []) {
    lines.push(`export function ${fn.name}() {`)
    lines.push(`  return ${nativeOnly}(${JSON.stringify(fn.name)})`)
    lines.push('}', '')
  }
  for (const cls of framework.classes ?? []) {
    const constructorDefinition = cls.constructors?.[0]
    const constructorParameters = (constructorDefinition?.parameters ?? []).map((parameter) => parameter.name).join(', ')
    const constructor = constructorDefinition ? `  constructor(${constructorParameters}) {\n    ${nativeOnly}(${JSON.stringify(`new ${cls.name}`)})\n  }` : ''
    lines.push(`export class ${cls.name} {`)
    if (constructor) lines.push(constructor)
    for (const method of cls.methods ?? []) {
      const prefix = method.static ? 'static ' : ''
      lines.push(`  ${prefix}${method.name}() {`)
      lines.push(`    return ${nativeOnly}(${JSON.stringify(`${cls.name}.${method.name}`)})`)
      lines.push('  }')
    }
    lines.push('}', '')
  }
  return `${lines.join('\n').trimEnd()}\n`
}

function appendFoundationStringConversions(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'Foundation')) return
  lines.push('#if __has_include(<Foundation/Foundation.h>)')
  lines.push('namespace gea::apple::Foundation {')
  lines.push('NSString *toNSString(const std::string &value) {')
  lines.push('  return [NSString stringWithUTF8String:value.c_str()];')
  lines.push('}')
  lines.push('std::string fromNSString(NSString *value) {')
  lines.push('  if (!value) return {};')
  lines.push('  const char *utf8 = [value UTF8String];')
  lines.push('  return utf8 ? std::string(utf8) : std::string();')
  lines.push('}')
  lines.push('}', '')
  lines.push('#endif', '')
}

function appendDispatchBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'Dispatch')) return
  lines.push('#if __has_include(<dispatch/dispatch.h>)')
  lines.push('void gea::apple::Dispatch::dispatchAsyncGlobal(std::function<void()> execute) {')
  lines.push('  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{')
  lines.push('    if (execute) execute();')
  lines.push('  });')
  lines.push('}')
  lines.push('void gea::apple::Dispatch::dispatchAsyncMain(std::function<void()> execute) {')
  lines.push('  dispatch_async(dispatch_get_main_queue(), ^{')
  lines.push('    if (execute) execute();')
  lines.push('  });')
  lines.push('}')
  lines.push('#endif', '')
}

function appendAVFoundationBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'AVFoundation')) return
  lines.push('#if __has_include(<AVFoundation/AVFoundation.h>)')
  lines.push('@interface GeaApplePhotoCaptureDelegate : NSObject <AVCapturePhotoCaptureDelegate>')
  lines.push('- (instancetype)initWithHandler:(std::function<void(gea::apple::Foundation::NSData, std::string)>)handler;')
  lines.push('@end', '')
  lines.push('static NSMutableSet *geaApplePhotoCaptureDelegates() {')
  lines.push('  static NSMutableSet *delegates = nil;')
  lines.push('  static dispatch_once_t onceToken;')
  lines.push('  dispatch_once(&onceToken, ^{ delegates = [NSMutableSet set]; });')
  lines.push('  return delegates;')
  lines.push('}', '')
  lines.push('@implementation GeaApplePhotoCaptureDelegate {')
  lines.push('  std::function<void(gea::apple::Foundation::NSData, std::string)> _handler;')
  lines.push('}')
  lines.push('- (instancetype)initWithHandler:(std::function<void(gea::apple::Foundation::NSData, std::string)>)handler {')
  lines.push('  self = [super init];')
  lines.push('  if (self) _handler = std::move(handler);')
  lines.push('  return self;')
  lines.push('}')
  lines.push('- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {')
  lines.push('  (void)output;')
  lines.push('  NSData *data = error ? nil : [photo fileDataRepresentation];')
  lines.push('  NSData *capturedData = data;')
  lines.push('  std::string message;')
  lines.push('  if (error) message = gea::apple::Foundation::fromNSString([error localizedDescription]);')
  lines.push('  else if (!data) message = "No photo data";')
  lines.push('  auto handler = _handler;')
  lines.push('  dispatch_async(dispatch_get_main_queue(), ^{')
  lines.push('    if (handler) handler(gea::apple::Foundation::NSData(gea::apple::objc::retain((__bridge void *)capturedData)), message);')
  lines.push('    [geaApplePhotoCaptureDelegates() removeObject:self];')
  lines.push('  });')
  lines.push('}')
  lines.push('@end', '')
  lines.push('gea::apple::AVFoundation::AVCaptureDeviceInput gea::apple::AVFoundation::AVCaptureDeviceInput_deviceInputWithDevice(gea::apple::AVFoundation::AVCaptureDevice device) {')
  lines.push('  NSError *error = nil;')
  lines.push('  ::AVCaptureDevice *nativeDevice = (__bridge ::AVCaptureDevice *)gea::apple::objc::object(device.handle);')
  lines.push('  ::AVCaptureDeviceInput *input = [::AVCaptureDeviceInput deviceInputWithDevice:nativeDevice error:&error];')
  lines.push('  if (!input && error) NSLog(@"AVCaptureDeviceInput creation failed: %@", error);')
  lines.push('  return gea::apple::AVFoundation::AVCaptureDeviceInput(gea::apple::objc::retain((__bridge void *)input));')
  lines.push('}')
  lines.push('bool gea::apple::AVFoundation::AVCaptureDevice_lockForConfiguration(gea::apple::AVFoundation::AVCaptureDevice device) {')
  lines.push('  NSError *error = nil;')
  lines.push('  ::AVCaptureDevice *nativeDevice = (__bridge ::AVCaptureDevice *)gea::apple::objc::object(device.handle);')
  lines.push('  if (!nativeDevice) return false;')
  lines.push('  BOOL locked = [nativeDevice lockForConfiguration:&error];')
  lines.push('  if (!locked && error) NSLog(@"AVCaptureDevice lockForConfiguration failed: %@", error);')
  lines.push('  return locked;')
  lines.push('}')
  lines.push('void gea::apple::AVFoundation::AVCaptureDevice_setExposureTargetBiasCompletionHandler(gea::apple::AVFoundation::AVCaptureDevice device, double bias, std::function<void(gea::apple::CoreMedia::CMTime)> handler) {')
  lines.push('  ::AVCaptureDevice *nativeDevice = (__bridge ::AVCaptureDevice *)gea::apple::objc::object(device.handle);')
  lines.push('  auto callback = handler;')
  lines.push('  if (!nativeDevice) {')
  lines.push('    if (callback) callback(kCMTimeInvalid);')
  lines.push('    return;')
  lines.push('  }')
  lines.push('  @try {')
  lines.push('    [nativeDevice setExposureTargetBias:bias completionHandler:^(CMTime syncTime) {')
  lines.push('      if (callback) callback(syncTime);')
  lines.push('    }];')
  lines.push('  } @catch (NSException *exception) {')
  lines.push('    NSString *reason = exception.reason ?: exception.name ?: @"AVCaptureDevice exposure bias failed";')
  lines.push('    NSLog(@"%@", reason);')
  lines.push('    if (callback) callback(kCMTimeInvalid);')
  lines.push('  }')
  lines.push('}')
  lines.push('void gea::apple::AVFoundation::AVCaptureDevice_setExposureModeCustomWithDurationISOCompletionHandler(gea::apple::AVFoundation::AVCaptureDevice device, gea::apple::CoreMedia::CMTime duration, double ISO, std::function<void(gea::apple::CoreMedia::CMTime)> handler) {')
  lines.push('  ::AVCaptureDevice *nativeDevice = (__bridge ::AVCaptureDevice *)gea::apple::objc::object(device.handle);')
  lines.push('  auto callback = handler;')
  lines.push('  if (!nativeDevice) {')
  lines.push('    if (callback) callback(kCMTimeInvalid);')
  lines.push('    return;')
  lines.push('  }')
  lines.push('  @try {')
  lines.push('    [nativeDevice setExposureModeCustomWithDuration:duration ISO:ISO completionHandler:^(CMTime syncTime) {')
  lines.push('      if (callback) callback(syncTime);')
  lines.push('    }];')
  lines.push('  } @catch (NSException *exception) {')
  lines.push('    NSString *reason = exception.reason ?: exception.name ?: @"AVCaptureDevice custom exposure failed";')
  lines.push('    NSLog(@"%@", reason);')
  lines.push('    if (callback) callback(kCMTimeInvalid);')
  lines.push('  }')
  lines.push('}')
  lines.push('std::vector<double> gea::apple::AVFoundation::AVCaptureDevice_get_virtualDeviceSwitchOverVideoZoomFactors(gea::apple::AVFoundation::AVCaptureDevice self) {')
  lines.push('  ::AVCaptureDevice *nativeDevice = (__bridge ::AVCaptureDevice *)gea::apple::objc::object(self.handle);')
  lines.push('  std::vector<double> factors;')
  lines.push('  if (!nativeDevice) return factors;')
  lines.push('  for (NSNumber *factor in nativeDevice.virtualDeviceSwitchOverVideoZoomFactors) {')
  lines.push('    factors.push_back([factor doubleValue]);')
  lines.push('  }')
  lines.push('  return factors;')
  lines.push('}')
  lines.push('void gea::apple::AVFoundation::AVCapturePhotoOutput_capturePhotoWithSettingsHandler(gea::apple::AVFoundation::AVCapturePhotoOutput output, gea::apple::AVFoundation::AVCapturePhotoSettings settings, std::function<void(gea::apple::Foundation::NSData, std::string)> handler) {')
  lines.push('  ::AVCapturePhotoOutput *nativeOutput = (__bridge ::AVCapturePhotoOutput *)gea::apple::objc::object(output.handle);')
  lines.push('  ::AVCapturePhotoSettings *nativeSettings = (__bridge ::AVCapturePhotoSettings *)gea::apple::objc::object(settings.handle);')
  lines.push('  if (!nativeOutput || !nativeSettings) {')
  lines.push('    if (handler) handler(gea::apple::Foundation::NSData(), "Missing AVCapturePhotoOutput or AVCapturePhotoSettings");')
  lines.push('    return;')
  lines.push('  }')
  lines.push('  auto callback = handler;')
  lines.push('  GeaApplePhotoCaptureDelegate *delegate = [[GeaApplePhotoCaptureDelegate alloc] initWithHandler:callback];')
  lines.push('  [geaApplePhotoCaptureDelegates() addObject:delegate];')
  lines.push('  @try {')
  lines.push('    [nativeOutput capturePhotoWithSettings:nativeSettings delegate:delegate];')
  lines.push('  } @catch (NSException *exception) {')
  lines.push('    [geaApplePhotoCaptureDelegates() removeObject:delegate];')
  lines.push('    NSString *reason = exception.reason ?: exception.name ?: @"AVCapturePhotoOutput capture failed";')
  lines.push('    if (callback) callback(gea::apple::Foundation::NSData(), gea::apple::Foundation::fromNSString(reason));')
  lines.push('  }')
  lines.push('}')
  lines.push('#endif', '')
}

function appendPhotosBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'Photos')) return
  lines.push('#if __has_include(<Photos/Photos.h>)')
  lines.push('static void geaApplePhotosDispatchSaveResult(std::function<void(bool, std::string)> handler, bool success, NSString *message) {')
  lines.push('  std::string text = gea::apple::Foundation::fromNSString(message);')
  lines.push('  dispatch_async(dispatch_get_main_queue(), ^{')
  lines.push('    if (handler) handler(success, text);')
  lines.push('  });')
  lines.push('}')
  lines.push('static void geaApplePhotosSaveImageDataAuthorized(NSData *data, std::function<void(bool, std::string)> handler) {')
  lines.push('  __block NSString *creationException = nil;')
  lines.push('  @try {')
  lines.push('    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{')
  lines.push('      @try {')
  lines.push('        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];')
  lines.push('        [request addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];')
  lines.push('      } @catch (NSException *exception) {')
  lines.push('        creationException = exception.reason ?: exception.name ?: @"Photos save failed";')
  lines.push('      }')
  lines.push('    } completionHandler:^(BOOL success, NSError *error) {')
  lines.push('      if (creationException) geaApplePhotosDispatchSaveResult(handler, false, creationException);')
  lines.push('      else geaApplePhotosDispatchSaveResult(handler, success, error ? [error localizedDescription] : @"");')
  lines.push('    }];')
  lines.push('  } @catch (NSException *exception) {')
  lines.push('    NSString *reason = exception.reason ?: exception.name ?: @"Photos save failed";')
  lines.push('    geaApplePhotosDispatchSaveResult(handler, false, reason);')
  lines.push('  }')
  lines.push('}')
  lines.push('void gea::apple::Photos::PHPhotoLibrary_saveImageData(gea::apple::Foundation::NSData data, std::function<void(bool, std::string)> handler) {')
  lines.push('  NSData *nativeData = (__bridge NSData *)gea::apple::objc::object(data.handle);')
  lines.push('  if (!nativeData) {')
  lines.push('    geaApplePhotosDispatchSaveResult(handler, false, @"Missing image data");')
  lines.push('    return;')
  lines.push('  }')
  lines.push('  NSData *imageData = [nativeData copy];')
  lines.push('  if (@available(iOS 14.0, *)) {')
  lines.push('    [::PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {')
  lines.push('      if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) geaApplePhotosSaveImageDataAuthorized(imageData, handler);')
  lines.push('      else geaApplePhotosDispatchSaveResult(handler, false, @"Photos add permission denied");')
  lines.push('    }];')
  lines.push('  } else {')
  lines.push('    [::PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {')
  lines.push('      if (status == PHAuthorizationStatusAuthorized) geaApplePhotosSaveImageDataAuthorized(imageData, handler);')
  lines.push('      else geaApplePhotosDispatchSaveResult(handler, false, @"Photos permission denied");')
  lines.push('    }];')
  lines.push('  }')
  lines.push('}')
  lines.push('#endif', '')
}

function appendMetalBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'Metal')) return
  lines.push('#if __has_include(<Metal/Metal.h>)')
  lines.push('namespace {')
  lines.push('id<MTLDevice> geaAppleMTLDevice(gea::apple::Metal::MTLDevice value) { return (__bridge id<MTLDevice>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLCommandQueue> geaAppleMTLCommandQueue(gea::apple::Metal::MTLCommandQueue value) { return (__bridge id<MTLCommandQueue>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLCommandBuffer> geaAppleMTLCommandBuffer(gea::apple::Metal::MTLCommandBuffer value) { return (__bridge id<MTLCommandBuffer>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLLibrary> geaAppleMTLLibrary(gea::apple::Metal::MTLLibrary value) { return (__bridge id<MTLLibrary>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLFunction> geaAppleMTLFunction(gea::apple::Metal::MTLFunction value) { return (__bridge id<MTLFunction>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLRenderPipelineState> geaAppleMTLRenderPipelineState(gea::apple::Metal::MTLRenderPipelineState value) { return (__bridge id<MTLRenderPipelineState>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLBuffer> geaAppleMTLBuffer(gea::apple::Metal::MTLBuffer value) { return (__bridge id<MTLBuffer>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLDepthStencilState> geaAppleMTLDepthStencilState(gea::apple::Metal::MTLDepthStencilState value) { return (__bridge id<MTLDepthStencilState>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLRenderCommandEncoder> geaAppleMTLRenderCommandEncoder(gea::apple::Metal::MTLRenderCommandEncoder value) { return (__bridge id<MTLRenderCommandEncoder>)gea::apple::objc::object(value.handle); }')
  lines.push('id<MTLDrawable> geaAppleMTLDrawable(gea::apple::Metal::MTLDrawable value) { return (__bridge id<MTLDrawable>)gea::apple::objc::object(value.handle); }')
  lines.push('MTLCompileOptions *geaAppleMTLCompileOptions(gea::apple::Metal::MTLCompileOptions value) { return (__bridge MTLCompileOptions *)gea::apple::objc::object(value.handle); }')
  lines.push('MTLRenderPipelineDescriptor *geaAppleMTLRenderPipelineDescriptor(gea::apple::Metal::MTLRenderPipelineDescriptor value) { return (__bridge MTLRenderPipelineDescriptor *)gea::apple::objc::object(value.handle); }')
  lines.push('MTLRenderPipelineColorAttachmentDescriptorArray *geaAppleMTLColorAttachments(gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptorArray value) { return (__bridge MTLRenderPipelineColorAttachmentDescriptorArray *)gea::apple::objc::object(value.handle); }')
  lines.push('MTLRenderPipelineColorAttachmentDescriptor *geaAppleMTLColorAttachment(gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor value) { return (__bridge MTLRenderPipelineColorAttachmentDescriptor *)gea::apple::objc::object(value.handle); }')
  lines.push('MTLRenderPassDescriptor *geaAppleMTLRenderPassDescriptor(gea::apple::Metal::MTLRenderPassDescriptor value) { return (__bridge MTLRenderPassDescriptor *)gea::apple::objc::object(value.handle); }')
  lines.push('MTLDepthStencilDescriptor *geaAppleMTLDepthStencilDescriptor(gea::apple::Metal::MTLDepthStencilDescriptor value) { return (__bridge MTLDepthStencilDescriptor *)gea::apple::objc::object(value.handle); }')
  lines.push('std::vector<float> geaAppleFloatBytes(const std::vector<double> &values) {')
  lines.push('  std::vector<float> storage;')
  lines.push('  storage.reserve(values.size());')
  lines.push('  for (double value : values) storage.push_back(static_cast<float>(value));')
  lines.push('  return storage;')
  lines.push('}')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLDevice gea::apple::Metal::MTLCreateSystemDefaultDevice() {')
  lines.push('  return gea::apple::Metal::MTLDevice(gea::apple::objc::retain((__bridge void *)::MTLCreateSystemDefaultDevice()));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLClearColor gea::apple::Metal::MTLClearColorMake(double red, double green, double blue, double alpha) {')
  lines.push('  return gea::apple::Metal::MTLClearColor{red, green, blue, alpha};')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLCompileOptions_init() {')
  lines.push('  return gea::apple::objc::retain((__bridge void *)[[::MTLCompileOptions alloc] init]);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLCommandQueue gea::apple::Metal::MTLDevice_newCommandQueue(gea::apple::Metal::MTLDevice self) {')
  lines.push('  return gea::apple::Metal::MTLCommandQueue(gea::apple::objc::retain((__bridge void *)[geaAppleMTLDevice(self) newCommandQueue]));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLLibrary gea::apple::Metal::MTLDevice_newLibraryWithSourceOptionsError(gea::apple::Metal::MTLDevice self, std::string source, gea::apple::Metal::MTLCompileOptions options) {')
  lines.push('  NSError *error = nil;')
  lines.push('  id<MTLLibrary> library = [geaAppleMTLDevice(self) newLibraryWithSource:gea::apple::Foundation::toNSString(source) options:geaAppleMTLCompileOptions(options) error:&error];')
  lines.push('  if (!library && error) NSLog(@"Metal library compilation failed: %@", error);')
  lines.push('  return gea::apple::Metal::MTLLibrary(gea::apple::objc::retain((__bridge void *)library));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLBuffer gea::apple::Metal::MTLDevice_newBufferWithBytesLengthOptions(gea::apple::Metal::MTLDevice self, std::vector<double> bytes, double length, double options) {')
  lines.push('  std::vector<float> storage = geaAppleFloatBytes(bytes);')
  lines.push('  const NSUInteger byteLength = static_cast<NSUInteger>(length);')
  lines.push('  id<MTLBuffer> buffer = [geaAppleMTLDevice(self) newBufferWithBytes:storage.data() length:byteLength options:static_cast<MTLResourceOptions>(options)];')
  lines.push('  return gea::apple::Metal::MTLBuffer(gea::apple::objc::retain((__bridge void *)buffer));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLRenderPipelineState gea::apple::Metal::MTLDevice_newRenderPipelineStateWithDescriptorError(gea::apple::Metal::MTLDevice self, gea::apple::Metal::MTLRenderPipelineDescriptor descriptor) {')
  lines.push('  NSError *error = nil;')
  lines.push('  id<MTLRenderPipelineState> state = [geaAppleMTLDevice(self) newRenderPipelineStateWithDescriptor:geaAppleMTLRenderPipelineDescriptor(descriptor) error:&error];')
  lines.push('  if (!state && error) NSLog(@"Metal pipeline creation failed: %@", error);')
  lines.push('  return gea::apple::Metal::MTLRenderPipelineState(gea::apple::objc::retain((__bridge void *)state));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLDepthStencilState gea::apple::Metal::MTLDevice_newDepthStencilStateWithDescriptor(gea::apple::Metal::MTLDevice self, gea::apple::Metal::MTLDepthStencilDescriptor descriptor) {')
  lines.push('  id<MTLDepthStencilState> state = [geaAppleMTLDevice(self) newDepthStencilStateWithDescriptor:geaAppleMTLDepthStencilDescriptor(descriptor)];')
  lines.push('  return gea::apple::Metal::MTLDepthStencilState(gea::apple::objc::retain((__bridge void *)state));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLCommandBuffer gea::apple::Metal::MTLCommandQueue_commandBuffer(gea::apple::Metal::MTLCommandQueue self) {')
  lines.push('  return gea::apple::Metal::MTLCommandBuffer(gea::apple::objc::retain((__bridge void *)[geaAppleMTLCommandQueue(self) commandBuffer]));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLRenderCommandEncoder gea::apple::Metal::MTLCommandBuffer_renderCommandEncoderWithDescriptor(gea::apple::Metal::MTLCommandBuffer self, gea::apple::Metal::MTLRenderPassDescriptor descriptor) {')
  lines.push('  return gea::apple::Metal::MTLRenderCommandEncoder(gea::apple::objc::retain((__bridge void *)[geaAppleMTLCommandBuffer(self) renderCommandEncoderWithDescriptor:geaAppleMTLRenderPassDescriptor(descriptor)]));')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLCommandBuffer_presentDrawable(gea::apple::Metal::MTLCommandBuffer self, gea::apple::Metal::MTLDrawable drawable) {')
  lines.push('  [geaAppleMTLCommandBuffer(self) presentDrawable:geaAppleMTLDrawable(drawable)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLCommandBuffer_commit(gea::apple::Metal::MTLCommandBuffer self) {')
  lines.push('  [geaAppleMTLCommandBuffer(self) commit];')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLFunction gea::apple::Metal::MTLLibrary_newFunctionWithName(gea::apple::Metal::MTLLibrary self, std::string name) {')
  lines.push('  return gea::apple::Metal::MTLFunction(gea::apple::objc::retain((__bridge void *)[geaAppleMTLLibrary(self) newFunctionWithName:gea::apple::Foundation::toNSString(name)]));')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLRenderPipelineDescriptor_init() {')
  lines.push('  return gea::apple::objc::retain((__bridge void *)[[::MTLRenderPipelineDescriptor alloc] init]);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLFunction gea::apple::Metal::MTLRenderPipelineDescriptor_get_vertexFunction(gea::apple::Metal::MTLRenderPipelineDescriptor self) {')
  lines.push('  return gea::apple::Metal::MTLFunction(gea::apple::objc::retain((__bridge void *)geaAppleMTLRenderPipelineDescriptor(self).vertexFunction));')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderPipelineDescriptor_set_vertexFunction(gea::apple::Metal::MTLRenderPipelineDescriptor self, gea::apple::Metal::MTLFunction value) {')
  lines.push('  geaAppleMTLRenderPipelineDescriptor(self).vertexFunction = geaAppleMTLFunction(value);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLFunction gea::apple::Metal::MTLRenderPipelineDescriptor_get_fragmentFunction(gea::apple::Metal::MTLRenderPipelineDescriptor self) {')
  lines.push('  return gea::apple::Metal::MTLFunction(gea::apple::objc::retain((__bridge void *)geaAppleMTLRenderPipelineDescriptor(self).fragmentFunction));')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderPipelineDescriptor_set_fragmentFunction(gea::apple::Metal::MTLRenderPipelineDescriptor self, gea::apple::Metal::MTLFunction value) {')
  lines.push('  geaAppleMTLRenderPipelineDescriptor(self).fragmentFunction = geaAppleMTLFunction(value);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptorArray gea::apple::Metal::MTLRenderPipelineDescriptor_get_colorAttachments(gea::apple::Metal::MTLRenderPipelineDescriptor self) {')
  lines.push('  return gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptorArray(gea::apple::objc::retain((__bridge void *)geaAppleMTLRenderPipelineDescriptor(self).colorAttachments));')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLRenderPipelineDescriptor_get_depthAttachmentPixelFormat(gea::apple::Metal::MTLRenderPipelineDescriptor self) {')
  lines.push('  return geaAppleMTLRenderPipelineDescriptor(self).depthAttachmentPixelFormat;')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderPipelineDescriptor_set_depthAttachmentPixelFormat(gea::apple::Metal::MTLRenderPipelineDescriptor self, double value) {')
  lines.push('  geaAppleMTLRenderPipelineDescriptor(self).depthAttachmentPixelFormat = static_cast<MTLPixelFormat>(value);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptorArray_objectAtIndexedSubscript(gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptorArray self, double index) {')
  lines.push('  return gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor(gea::apple::objc::retain((__bridge void *)[geaAppleMTLColorAttachments(self) objectAtIndexedSubscript:static_cast<NSUInteger>(index)]));')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor_get_pixelFormat(gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor self) {')
  lines.push('  return geaAppleMTLColorAttachment(self).pixelFormat;')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor_set_pixelFormat(gea::apple::Metal::MTLRenderPipelineColorAttachmentDescriptor self, double value) {')
  lines.push('  geaAppleMTLColorAttachment(self).pixelFormat = static_cast<MTLPixelFormat>(value);')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLDepthStencilDescriptor_init() {')
  lines.push('  return gea::apple::objc::retain((__bridge void *)[[::MTLDepthStencilDescriptor alloc] init]);')
  lines.push('}', '')
  lines.push('double gea::apple::Metal::MTLDepthStencilDescriptor_get_depthCompareFunction(gea::apple::Metal::MTLDepthStencilDescriptor self) {')
  lines.push('  return geaAppleMTLDepthStencilDescriptor(self).depthCompareFunction;')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLDepthStencilDescriptor_set_depthCompareFunction(gea::apple::Metal::MTLDepthStencilDescriptor self, double value) {')
  lines.push('  geaAppleMTLDepthStencilDescriptor(self).depthCompareFunction = static_cast<MTLCompareFunction>(value);')
  lines.push('}', '')
  lines.push('bool gea::apple::Metal::MTLDepthStencilDescriptor_get_depthWriteEnabled(gea::apple::Metal::MTLDepthStencilDescriptor self) {')
  lines.push('  return geaAppleMTLDepthStencilDescriptor(self).depthWriteEnabled;')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLDepthStencilDescriptor_set_depthWriteEnabled(gea::apple::Metal::MTLDepthStencilDescriptor self, bool value) {')
  lines.push('  geaAppleMTLDepthStencilDescriptor(self).depthWriteEnabled = value;')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_setRenderPipelineState(gea::apple::Metal::MTLRenderCommandEncoder self, gea::apple::Metal::MTLRenderPipelineState pipelineState) {')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) setRenderPipelineState:geaAppleMTLRenderPipelineState(pipelineState)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_setDepthStencilState(gea::apple::Metal::MTLRenderCommandEncoder self, gea::apple::Metal::MTLDepthStencilState depthStencilState) {')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) setDepthStencilState:geaAppleMTLDepthStencilState(depthStencilState)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_setVertexBufferOffsetAtIndex(gea::apple::Metal::MTLRenderCommandEncoder self, gea::apple::Metal::MTLBuffer buffer, double offset, double index) {')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) setVertexBuffer:geaAppleMTLBuffer(buffer) offset:static_cast<NSUInteger>(offset) atIndex:static_cast<NSUInteger>(index)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_setVertexBytesLengthAtIndex(gea::apple::Metal::MTLRenderCommandEncoder self, std::vector<double> bytes, double length, double index) {')
  lines.push('  std::vector<float> storage = geaAppleFloatBytes(bytes);')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) setVertexBytes:storage.data() length:static_cast<NSUInteger>(length) atIndex:static_cast<NSUInteger>(index)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_drawPrimitivesVertexStartVertexCount(gea::apple::Metal::MTLRenderCommandEncoder self, double primitiveType, double vertexStart, double vertexCount) {')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) drawPrimitives:static_cast<MTLPrimitiveType>(primitiveType) vertexStart:static_cast<NSUInteger>(vertexStart) vertexCount:static_cast<NSUInteger>(vertexCount)];')
  lines.push('}', '')
  lines.push('void gea::apple::Metal::MTLRenderCommandEncoder_endEncoding(gea::apple::Metal::MTLRenderCommandEncoder self) {')
  lines.push('  [geaAppleMTLRenderCommandEncoder(self) endEncoding];')
  lines.push('}')
  lines.push('#endif', '')
}

function appendMetalKitBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'MetalKit')) return
  lines.push('#if __has_include(<MetalKit/MetalKit.h>)')
  lines.push('@interface GeaAppleMTKViewDelegate : NSObject <MTKViewDelegate>')
  lines.push('- (instancetype)initWithDrawCallback:(std::function<void()>)drawCallback;')
  lines.push('@end', '')
  lines.push('@implementation GeaAppleMTKViewDelegate {')
  lines.push('  std::function<void()> _drawCallback;')
  lines.push('}')
  lines.push('- (instancetype)initWithDrawCallback:(std::function<void()>)drawCallback {')
  lines.push('  self = [super init];')
  lines.push('  if (self) _drawCallback = std::move(drawCallback);')
  lines.push('  return self;')
  lines.push('}')
  lines.push('- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {')
  lines.push('  (void)view;')
  lines.push('  (void)size;')
  lines.push('}')
  lines.push('- (void)drawInMTKView:(MTKView *)view {')
  lines.push('  (void)view;')
  lines.push('  if (_drawCallback) _drawCallback();')
  lines.push('}')
  lines.push('@end', '')
  lines.push('double gea::apple::MetalKit::MTKView_init() {')
  lines.push('  return gea::apple::objc::retain((__bridge void *)[[::MTKView alloc] init]);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLDevice gea::apple::MetalKit::MTKView_get_device(gea::apple::MetalKit::MTKView self) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  return gea::apple::Metal::MTLDevice(gea::apple::objc::retain((__bridge void *)view.device));')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_device(gea::apple::MetalKit::MTKView self, gea::apple::Metal::MTLDevice value) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  view.device = (__bridge id<MTLDevice>)gea::apple::objc::object(value.handle);')
  lines.push('}', '')
  lines.push('gea::apple::MetalKit::MTKViewDelegate gea::apple::MetalKit::MTKView_get_delegate(gea::apple::MetalKit::MTKView self) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  return gea::apple::MetalKit::MTKViewDelegate(gea::apple::objc::retain((__bridge void *)view.delegate));')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_delegate(gea::apple::MetalKit::MTKView self, gea::apple::MetalKit::MTKViewDelegate value) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  view.delegate = (__bridge id<MTKViewDelegate>)gea::apple::objc::object(value.handle);')
  lines.push('}', '')
  lines.push('double gea::apple::MetalKit::MTKView_get_colorPixelFormat(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).colorPixelFormat;')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_colorPixelFormat(gea::apple::MetalKit::MTKView self, double value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).colorPixelFormat = static_cast<MTLPixelFormat>(value);')
  lines.push('}', '')
  lines.push('double gea::apple::MetalKit::MTKView_get_depthStencilPixelFormat(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).depthStencilPixelFormat;')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_depthStencilPixelFormat(gea::apple::MetalKit::MTKView self, double value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).depthStencilPixelFormat = static_cast<MTLPixelFormat>(value);')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLClearColor gea::apple::MetalKit::MTKView_get_clearColor(gea::apple::MetalKit::MTKView self) {')
  lines.push('  ::MTLClearColor color = ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).clearColor;')
  lines.push('  return gea::apple::Metal::MTLClearColor{color.red, color.green, color.blue, color.alpha};')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_clearColor(gea::apple::MetalKit::MTKView self, gea::apple::Metal::MTLClearColor value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).clearColor = ::MTLClearColorMake(value.red, value.green, value.blue, value.alpha);')
  lines.push('}', '')
  lines.push('double gea::apple::MetalKit::MTKView_get_preferredFramesPerSecond(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).preferredFramesPerSecond;')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_preferredFramesPerSecond(gea::apple::MetalKit::MTKView self, double value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).preferredFramesPerSecond = static_cast<NSInteger>(value);')
  lines.push('}', '')
  lines.push('bool gea::apple::MetalKit::MTKView_get_enableSetNeedsDisplay(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).enableSetNeedsDisplay;')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_enableSetNeedsDisplay(gea::apple::MetalKit::MTKView self, bool value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).enableSetNeedsDisplay = value;')
  lines.push('}', '')
  lines.push('bool gea::apple::MetalKit::MTKView_get_paused(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).paused;')
  lines.push('}', '')
  lines.push('void gea::apple::MetalKit::MTKView_set_paused(gea::apple::MetalKit::MTKView self, bool value) {')
  lines.push('  ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).paused = value;')
  lines.push('}', '')
  lines.push('gea::apple::CoreGraphics::CGSize gea::apple::MetalKit::MTKView_get_drawableSize(gea::apple::MetalKit::MTKView self) {')
  lines.push('  return ((__bridge ::MTKView *)gea::apple::objc::object(self.handle)).drawableSize;')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLRenderPassDescriptor gea::apple::MetalKit::MTKView_get_currentRenderPassDescriptor(gea::apple::MetalKit::MTKView self) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  return gea::apple::Metal::MTLRenderPassDescriptor(gea::apple::objc::retain((__bridge void *)view.currentRenderPassDescriptor));')
  lines.push('}', '')
  lines.push('gea::apple::Metal::MTLDrawable gea::apple::MetalKit::MTKView_get_currentDrawable(gea::apple::MetalKit::MTKView self) {')
  lines.push('  ::MTKView *view = (__bridge ::MTKView *)gea::apple::objc::object(self.handle);')
  lines.push('  return gea::apple::Metal::MTLDrawable(gea::apple::objc::retain((__bridge void *)view.currentDrawable));')
  lines.push('}', '')
  lines.push('gea::apple::MetalKit::MTKViewDelegate gea::apple::MetalKit::MTKViewDelegate_create(std::function<void()> drawInMTKView) {')
  lines.push('  GeaAppleMTKViewDelegate *delegate = [[GeaAppleMTKViewDelegate alloc] initWithDrawCallback:std::move(drawInMTKView)];')
  lines.push('  return gea::apple::MetalKit::MTKViewDelegate(gea::apple::objc::retain((__bridge void *)delegate));')
  lines.push('}')
  lines.push('#endif', '')
}

function appendUIKitCallbackBridges(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'UIKit')) return
  lines.push('#if __has_include(<UIKit/UIKit.h>)')
  lines.push('@implementation GeaAppleObjCTarget')
  lines.push('- (instancetype)initWithCallback:(std::function<void()>)callback {')
  lines.push('  self = [super init];')
  lines.push('  if (self) _callback = std::move(callback);')
  lines.push('  return self;')
  lines.push('}')
  lines.push('- (void)invoke:(id)sender {')
  lines.push('  (void)sender;')
  lines.push('  if (_callback) _callback();')
  lines.push('}')
  lines.push('@end')
  lines.push('#endif', '')
}

function appendUIKitCallbackBridgeDeclarations(lines: string[], metadata: AppleBridgeMetadata): void {
  if (!metadata.frameworks.some((framework) => framework.name === 'UIKit')) return
  lines.push('#if __has_include(<UIKit/UIKit.h>)')
  lines.push('@interface GeaAppleObjCTarget : NSObject {')
  lines.push('  std::function<void()> _callback;')
  lines.push('}')
  lines.push('- (instancetype)initWithCallback:(std::function<void()>)callback;')
  lines.push('- (void)invoke:(id)sender;')
  lines.push('@end')
  lines.push('#endif', '')
}

function defaultInitializer(type: AppleTypeReference): string {
  if (type.kind === 'primitive') {
    if (type.name === 'number') return ' = 0'
    if (type.name === 'boolean') return ' = false'
    if (type.name === 'string') return ''
  }
  return ''
}

function functionMetadata(framework: string, fn: AppleFunctionDefinition): AppleBridgeFunctionMetadata {
  return {
    framework,
    name: fn.name,
    thunk: frameworkFunctionThunk(framework, fn.name),
    returns: fn.returns,
    parameters: fn.parameters ?? [],
  }
}

function methodMetadata(framework: string, cls: string, method: AppleMethodDefinition): AppleBridgeMethodMetadata {
  const thunk = specialMethodThunk(framework, cls, method.name) ?? methodThunk(framework, cls, method.name)
  return {
    name: method.name,
    selector: method.selector,
    thunk,
    returns: method.returns,
    parameters: method.parameters ?? [],
    ...(method.static ? { static: true } : {}),
  }
}

function specialMethodThunk(framework: string, cls: string, method: string): string | undefined {
  if (framework === 'AVFoundation' && cls === 'AVCaptureDeviceInput' && method === 'deviceInputWithDevice') {
    return bridgeFunctionName(framework, `${cls}_${method}`)
  }
  if (framework === 'AVFoundation' && cls === 'AVCaptureDevice' && method === 'lockForConfiguration') {
    return bridgeFunctionName(framework, `${cls}_${method}`)
  }
  return undefined
}

function propertyMetadata(framework: string, cls: string, property: ApplePropertyDefinition): AppleBridgePropertyMetadata {
  return {
    name: property.name,
    getter: propertyThunk(framework, cls, property.name, 'get'),
    ...(property.readonly ? {} : { setter: propertyThunk(framework, cls, property.name, 'set') }),
    type: property.type,
  }
}

function parametersSignature(parameters: AppleParameterDefinition[], localFramework: string): string {
  return parameters.map((parameter) => `${parameter.name}: ${typeScriptType(parameter.type, localFramework)}`).join(', ')
}

function typeScriptType(type: AppleTypeReference, localFramework: string): string {
  const base = (() => {
    if (type.kind === 'function') {
      return `(${parametersSignature(type.parameters ?? [], localFramework)}) => ${typeScriptType(type.returns, localFramework)}`
    }
    if (type.kind === 'array') {
      return `${typeScriptType(type.element, localFramework)}[]`
    }
    if (type.kind === 'primitive') {
      if (type.name === 'void') return 'void'
      if (type.name === 'boolean') return 'boolean'
      if (type.name === 'string') return 'string'
      if (type.name === 'selector') return 'Selector'
      return 'number'
    }
    const [framework, name] = splitQualifiedName(type.name, localFramework)
    return framework === localFramework ? name : name
  })()
  return type.nullable && base !== 'void' ? `${base} | null` : base
}

function cppValueType(
  type: AppleTypeReference,
  localFramework: string,
  options: { preferLocalNames?: boolean } = {},
): string {
  if (type.kind === 'function') {
    const returns = cppValueType(type.returns, localFramework, options)
    const params = (type.parameters ?? []).map((parameter) => cppValueType(parameter.type, localFramework, options)).join(', ')
    return `std::function<${returns}(${params})>`
  }
  if (type.kind === 'array') {
    return `std::vector<${cppValueType(type.element, localFramework, options)}>`
  }
  if (type.kind === 'primitive') {
    if (type.name === 'void') return 'void'
    if (type.name === 'boolean') return 'bool'
    if (type.name === 'number') return 'double'
    if (type.name === 'string') return 'std::string'
    if (type.name === 'selector') return 'SEL'
    return type.name
  }
  const [framework, name] = splitQualifiedName(type.name, localFramework)
  if (options.preferLocalNames && framework === localFramework) return name
  return `::gea::apple::${framework}::${name}`
}

function frameworkUsesPrimitive(framework: AppleFrameworkDefinition, primitiveName: string): boolean {
  const matches = (type: AppleTypeReference): boolean => {
    if (type.kind === 'function') {
      return matches(type.returns) || (type.parameters ?? []).some((parameter) => matches(parameter.type))
    }
    if (type.kind === 'array') return matches(type.element)
    return type.kind === 'primitive' && type.name === primitiveName
  }
  if ((framework.constants ?? []).some((constant) => matches(constant.type))) return true
  if ((framework.functions ?? []).some((fn) => matches(fn.returns) || (fn.parameters ?? []).some((parameter) => matches(parameter.type)))) return true
  if ((framework.structs ?? []).some((struct) => struct.fields.some((field) => matches(field.type)))) return true
  return (framework.classes ?? []).some((cls) => {
    const constructors = (cls.constructors ?? []).some((method) => matches(method.returns) || (method.parameters ?? []).some((parameter) => matches(parameter.type)))
    const methods = (cls.methods ?? []).some((method) => matches(method.returns) || (method.parameters ?? []).some((parameter) => matches(parameter.type)))
    const properties = (cls.properties ?? []).some((property) => matches(property.type))
    return constructors || methods || properties
  })
}

function splitQualifiedName(name: string, fallbackFramework: string): [string, string] {
  const dot = name.indexOf('.')
  if (dot < 0) return [fallbackFramework, name]
  return [name.slice(0, dot), name.slice(dot + 1)]
}

function shortTypeName(name: string): string {
  return splitQualifiedName(name, '')[1]
}

function qualifiedName(framework: string, name: string): string {
  return `${framework}.${name}`
}

function cppTypeName(framework: string, name: string): string {
  return `gea::apple::${framework}::${name}`
}

function constructorThunk(framework: string, cls: string): string {
  return bridgeFunctionName(framework, `${cls}_init`)
}

function frameworkFunctionThunk(framework: string, fn: string): string {
  return bridgeFunctionName(framework, fn)
}

function methodThunk(framework: string, cls: string, method: string): string {
  return bridgeFunctionName(framework, `${cls}_${method}`)
}

function propertyThunk(framework: string, cls: string, property: string, kind: 'get' | 'set'): string {
  return bridgeFunctionName(framework, `${cls}_${kind}_${property}`)
}

function bridgeFunctionName(framework: string, name: string): string {
  return `gea::apple::${framework}::${name}`
}

function cppFunctionTarget(name: string): { namespaceName: string | null; bareName: string } {
  const qualifiedName = name.replace(/^::/, '')
  const separator = qualifiedName.lastIndexOf('::')
  if (separator < 0) return { namespaceName: null, bareName: qualifiedName }
  return {
    namespaceName: qualifiedName.slice(0, separator),
    bareName: qualifiedName.slice(separator + 2),
  }
}

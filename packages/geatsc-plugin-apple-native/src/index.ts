import fs from 'node:fs'
import path from 'node:path'

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

export interface AppleBridgeMetadata {
  frameworks: Array<{ name: string; bridgeHeaders?: string[] }>
  constants?: Record<string, AppleBridgeConstantMetadata>
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
  constructor?: { selector: string; thunk: string; parameters?: AppleParameterDefinition[] }
  methods: Record<string, AppleBridgeMethodMetadata>
  properties: Record<string, AppleBridgePropertyMetadata>
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

export interface HostShimDefinitions {
  hostNamespaces?: Record<string, string>
  hostNamespaceMethods?: Record<string, Record<string, string>>
  embeddedHostClasses?: Record<string, { factory?: string; wrapper: string; allowConcrete?: boolean; construct?: string }>
  nativeMemberMethods?: Record<string, NativeMemberBinding[]>
  nativeMemberPropertyGetters?: Record<string, NativeMemberBinding[]>
  nativeMemberPropertySetters?: Record<string, NativeMemberBinding[]>
  nativeNamespaceMethods?: Record<string, Record<string, { emit: string; returnType?: string }>>
  nativeTypes?: Record<string, string>
  embeddedHostFunctions?: Record<string, string>
  embeddedHostFunctionFrameworkVariants?: Record<string, Record<string, string>>
  embeddedHostFunctionReturnTypes?: Record<string, string>
  embeddedHostConstants?: Record<string, { emit: string; type: string }>
  hostExternDeclarations?: Record<string, string[]>
}

export interface NativeMemberBinding {
  extern?: string
  receiverTypes?: string[]
  emit?: string
  returnType?: string
  // Opt-in for the emitter's dynamic-receiver fallback: a boxed
  // (gea_cpp_value) receiver may be reconstructed as a native wrapper from
  // the handle the boxed value carries (see the compiler's
  // nativeMemberBindingFor). Set automatically for `{receiver}.handle`
  // emit templates in appendNativeMemberBinding.
  allowDynamicReceiver?: boolean
}

export interface PluginOptionMap {
  [key: string]: string
}

export interface PluginCompileContext {
  entry: string
  outDir?: string
  options: PluginOptionMap
}

export interface PluginCppContext {
  entry: string
  outDir: string
  options: PluginOptionMap
}

export interface CppGeneratedSource {
  fileName: string
  source: string
}

export interface GeatscPlugin {
  name: string
  configure?(context: PluginCompileContext): { allowAny?: boolean; hostShims?: HostShimDefinitions } | void
  createCppBackend?(context: PluginCppContext): { transformGeneratedSources?(sources: CppGeneratedSource[]): CppGeneratedSource[] } | undefined
}

export interface AppleNativePluginOptions {
  metadata?: AppleBridgeMetadata
  metadataPath?: string
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

const objcBackedFrameworks = new Set(['AVFoundation', 'CoreLocation', 'Foundation', 'MapKit', 'QuartzCore', 'UIKit', 'Photos', 'AppKit'])
const directCFunctionNames = new Set([
  'CGPointMake',
  'CGRectMake',
  'CGSizeMake',
  'CMTimeMakeWithSeconds',
  'CLLocationCoordinate2DMake',
  'MKCoordinateRegionMakeWithDistance',
])
const nativeStructFrameworks = new Set(['CoreGraphics', 'CoreLocation', 'CoreMedia', 'MapKit'])

export function appleNativePlugin(options: AppleNativePluginOptions = {}): GeatscPlugin {
  let metadata = options.metadata ?? null
  return {
    name: 'apple-native',
    configure(context) {
      metadata = metadata ?? loadMetadata(options.metadataPath ?? context.options['apple.metadata'], context.entry)
      if (!metadata) return
      return {
        hostShims: createAppleHostShims(metadata),
      }
    },
    createCppBackend(context) {
      const loadedMetadata = metadata
      if (!loadedMetadata) return undefined
      return {
        transformGeneratedSources(sources) {
          writeAppleNativeBridgeRuntime(loadedMetadata, context.outDir)
          const programSource = sources.map((source) => source.source).join('\n')
          // includeRuntime MUST be true: the inserted preamble contains the
          // `gea::apple::bridge` helpers (e.g. numberVectorFromValues) that reference
          // `gea::runtime::coerce::to_number` and iterate `std::vector<gea_cpp_value>`
          // (which needs a COMPLETE gea_cpp_value). generated_support.hpp already
          // `#include "runtime_pch.h"` further down, but the preamble is inserted at
          // the TOP — so without the runtime here, the helpers see only the forward
          // declaration from native_bridge.h. ObjC++ tolerated it; the plain-C++ (cxx)
          // PCH path does not ("no member 'runtime' in namespace 'gea'"). The runtime
          // include is idempotent (GEATSC_RUNTIME_PCH_INCLUDED guard) and a no-op under
          // -include-pch, so this stays compatible with the cxx-PCH optimization.
          const bridgePreamble = appleBridgePreamble(loadedMetadata, programSource, { includeRuntime: true })
          return sources.map((source) => (
            source.fileName === 'generated_support.hpp'
              ? { ...source, source: insertAppleBridgePreamble(source.source, bridgePreamble) }
              : source
          ))
        },
      }
    },
  }
}

export function createAppleHostShims(metadata: AppleBridgeMetadata): HostShimDefinitions {
  const hostNamespaces: Record<string, string> = {}
  const hostNamespaceMethods: Record<string, Record<string, string>> = {}
  const embeddedHostClasses: Record<string, { factory?: string; wrapper: string; allowConcrete?: boolean; construct?: string }> = {}
  const nativeMemberMethods: Record<string, NativeMemberBinding[]> = {}
  const nativeMemberPropertyGetters: Record<string, NativeMemberBinding[]> = {}
  const nativeMemberPropertySetters: Record<string, NativeMemberBinding[]> = {}
  const nativeNamespaceMethods: Record<string, Record<string, { emit: string; returnType?: string }>> = {}
  const nativeTypes: Record<string, string> = {}
  const embeddedHostFunctions: Record<string, string> = {}
  const embeddedHostFunctionFrameworkVariants: Record<string, Record<string, string>> = {}
  const embeddedHostFunctionReturnTypes: Record<string, string> = {}
  const embeddedHostConstants: Record<string, { emit: string; type: string }> = {}
  const hostExternDeclarations: Record<string, string[]> = {}
  const descendantClasses = descendantClassesByQualifiedName(metadata)

  appendAppleHostConstants(embeddedHostConstants, metadata)

  for (const struct of Object.values(metadata.structs ?? {})) {
    const typeName = cppType({ kind: 'struct', name: `${struct.framework}.${struct.name}` }, struct.framework)
    nativeTypes[struct.name] = typeName
    nativeTypes[`${struct.framework}.${struct.name}`] = typeName
  }

  for (const cls of Object.values(metadata.classes ?? {})) {
    nativeTypes[cls.name] = cls.wrapper
    nativeTypes[`${cls.framework}.${cls.name}`] = cls.wrapper
    embeddedHostClasses[cls.name] = {
      wrapper: cls.wrapper,
      allowConcrete: true,
    }
  }

  // Bare function names shared by more than one framework (e.g. `installRootView`
  // in UIKit and AppKit) collide in the flat `embeddedHostFunctions` map — the last
  // framework processed wins. For those, also record a per-framework variant keyed
  // by the placeholder's native-only marker so the emitter can pick the framework
  // matching the imported binding instead of the arbitrary collision winner.
  const functionFrameworksByName = new Map<string, Set<string>>()
  for (const fn of Object.values(metadata.functions ?? {})) {
    let frameworks = functionFrameworksByName.get(fn.name)
    if (!frameworks) functionFrameworksByName.set(fn.name, (frameworks = new Set()))
    frameworks.add(fn.framework)
  }

  for (const fn of Object.values(metadata.functions ?? {})) {
    const params = fn.parameters.map((parameter) => `${cppType(parameter.type, fn.framework)} ${parameter.name}`)
    const emit = directCFunctionNames.has(fn.name) ? `::${fn.name}` : fn.thunk
    if (directCFunctionNames.has(fn.name)) {
      embeddedHostFunctions[fn.name] = emit
    } else {
      embeddedHostFunctions[fn.name] = emit
      hostExternDeclarations[fn.thunk] = bridgeDeclaration(fn.thunk, cppType(fn.returns, fn.framework), params.join(', '))
    }
    if ((functionFrameworksByName.get(fn.name)?.size ?? 0) > 1) {
      const markerName = `geaApple${fn.framework}NativeOnly`
      ;(embeddedHostFunctionFrameworkVariants[fn.name] ??= {})[markerName] = emit
    }
    embeddedHostFunctionReturnTypes[fn.name] = cppType(fn.returns, fn.framework)
  }

  for (const cls of Object.values(metadata.classes)) {
    const receiverTypes = receiverTypesForClass(cls, descendantClasses)
    const constructor = Object.prototype.hasOwnProperty.call(cls, 'constructor') ? cls.constructor : undefined
    if (constructor) {
      const construct = objcBackedFrameworks.has(cls.framework)
        ? `${cls.wrapper}(gea::apple::objc::retain((__bridge void *)${objcAllocInitExpression(cls.name, constructor.selector, constructor.parameters ?? [])}))`
        : undefined
      embeddedHostClasses[cls.name] = {
        ...embeddedHostClasses[cls.name],
        ...(construct ? { construct } : { factory: constructor.thunk }),
      }
      if (!construct) hostExternDeclarations[constructor.thunk] = bridgeDeclaration(constructor.thunk, 'double', '')
    }
    for (const method of Object.values(cls.methods)) {
      const canEmitObjC = objcBackedFrameworks.has(cls.framework)
      if (method.static) {
        hostNamespaces[cls.name] = cls.name
        if ((cls.framework === 'UIKit' || cls.framework === 'AppKit') && cls.name === 'ObjCTarget' && method.name === 'create') {
          nativeNamespaceMethods[cls.name] = {
            ...(nativeNamespaceMethods[cls.name] ?? {}),
            [method.name]: {
              emit: '([&]() { GeaAppleObjCTarget *__gea_target = [[GeaAppleObjCTarget alloc] initWithCallback:std::function<void()>({arg0})]; return gea::apple::Foundation::NSObject(gea::apple::objc::retain((__bridge void *)__gea_target)); })()',
              returnType: 'gea::apple::Foundation::NSObject',
            },
          }
          continue
        }
        if (cls.framework === 'MetalKit' && cls.name === 'MTKViewDelegate' && method.name === 'create') {
          nativeNamespaceMethods[cls.name] = {
            ...(nativeNamespaceMethods[cls.name] ?? {}),
            [method.name]: {
              emit: `${method.thunk}(std::function<void()>({arg0}))`,
              returnType: 'gea::apple::MetalKit::MTKViewDelegate',
            },
          }
          hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'gea::apple::MetalKit::MTKViewDelegate', 'std::function<void()> drawInMTKView')
          continue
        }
        if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDeviceInput' && method.name === 'deviceInputWithDevice') {
          nativeNamespaceMethods[cls.name] = {
            ...(nativeNamespaceMethods[cls.name] ?? {}),
            [method.name]: {
              emit: `${method.thunk}({arg0})`,
              returnType: 'gea::apple::AVFoundation::AVCaptureDeviceInput',
            },
          }
          hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'gea::apple::AVFoundation::AVCaptureDeviceInput', 'gea::apple::AVFoundation::AVCaptureDevice device')
          continue
        }
        if (cls.framework === 'Photos' && cls.name === 'PHPhotoLibrary' && method.name === 'saveImageData') {
          nativeNamespaceMethods[cls.name] = {
            ...(nativeNamespaceMethods[cls.name] ?? {}),
            [method.name]: {
              emit: `${method.thunk}({arg0}, std::function<void(bool, std::string)>({arg1}))`,
              returnType: 'void',
            },
          }
          hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'void', 'gea::apple::Foundation::NSData data, std::function<void(bool, std::string)> handler')
          continue
        }
        if (canEmitObjC) {
          nativeNamespaceMethods[cls.name] = {
            ...(nativeNamespaceMethods[cls.name] ?? {}),
            [method.name]: {
              emit: objcReturnExpression(method.returns, cls.framework, objcMessageSendTemplate(cls.name, method.selector, method.parameters)),
              returnType: cppType(method.returns, cls.framework),
            },
          }
        } else {
          const params = method.parameters.map((parameter) => `${cppType(parameter.type, cls.framework)} ${parameter.name}`)
          hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, cppType(method.returns, cls.framework), params.join(', '))
          hostNamespaceMethods[cls.name] = {
            ...(hostNamespaceMethods[cls.name] ?? {}),
            [method.name]: method.thunk,
          }
        }
      } else {
        if (canEmitObjC) {
          if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'lockForConfiguration') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: `${method.thunk}({receiver})`,
              receiverTypes,
              returnType: 'bool',
            })
            hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'bool', 'gea::apple::AVFoundation::AVCaptureDevice device')
            continue
          }
          if (cls.framework === 'AVFoundation' && cls.name === 'AVCapturePhotoOutput' && method.name === 'capturePhotoWithSettingsHandler') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: `${method.thunk}({receiver}, {arg0}, std::function<void(gea::apple::Foundation::NSData, std::string)>({arg1}))`,
              receiverTypes,
              returnType: 'void',
            })
            hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'void', 'gea::apple::AVFoundation::AVCapturePhotoOutput output, gea::apple::AVFoundation::AVCapturePhotoSettings settings, std::function<void(gea::apple::Foundation::NSData, std::string)> handler')
            continue
          }
          if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'setExposureTargetBiasCompletionHandler') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: `${method.thunk}({receiver}, {arg0}, std::function<void(gea::apple::CoreMedia::CMTime)>({arg1}))`,
              receiverTypes,
              returnType: 'void',
            })
            hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'void', 'gea::apple::AVFoundation::AVCaptureDevice device, double bias, std::function<void(gea::apple::CoreMedia::CMTime)> handler')
            continue
          }
          if (cls.framework === 'AVFoundation' && cls.name === 'AVCaptureDevice' && method.name === 'setExposureModeCustomWithDurationISOCompletionHandler') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: `${method.thunk}({receiver}, {arg0}, {arg1}, std::function<void(gea::apple::CoreMedia::CMTime)>({arg2}))`,
              receiverTypes,
              returnType: 'void',
            })
            hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, 'void', 'gea::apple::AVFoundation::AVCaptureDevice device, gea::apple::CoreMedia::CMTime duration, double ISO, std::function<void(gea::apple::CoreMedia::CMTime)> handler')
            continue
          }
          if (cls.framework === 'UIKit' && cls.name === 'UIViewController' && method.name === 'presentViewControllerAnimatedCompletion') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: '([&]() { auto __gea_completion = std::function<void()>({arg2}); [((__bridge ::UIViewController *)gea::apple::objc::object({receiver}.handle)) presentViewController:((__bridge ::UIViewController *)gea::apple::objc::object({arg0}.handle)) animated:{arg1} completion:^{ if (__gea_completion) __gea_completion(); }]; })()',
              receiverTypes,
              returnType: 'void',
            })
            continue
          }
          if (cls.framework === 'UIKit' && cls.name === 'UIViewController' && method.name === 'dismissViewControllerAnimatedCompletion') {
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: '([&]() { auto __gea_completion = std::function<void()>({arg1}); [((__bridge ::UIViewController *)gea::apple::objc::object({receiver}.handle)) dismissViewControllerAnimated:{arg0} completion:^{ if (__gea_completion) __gea_completion(); }]; })()',
              receiverTypes,
              returnType: 'void',
            })
            continue
          }
          if (cls.framework === 'AppKit' && method.name === 'attachTextDelegate') {
            // Set the delegate AND explicitly register it for the text-change
            // notifications. NSTextView's setDelegate: does not reliably
            // auto-register textDidChange:, so the explicit NSNotificationCenter
            // observation guarantees the live write-back fires for both the title
            // (NSTextField → NSControlTextDidChangeNotification) and the body
            // (NSTextView → NSTextDidChangeNotification).
            appendNativeMemberBinding(nativeMemberMethods, method.name, {
              emit: '([&]() { id __gea_view = (__bridge id)gea::apple::objc::object({receiver}.handle); id __gea_obs = (__bridge id)gea::apple::objc::object({arg0}.handle); if ([__gea_view respondsToSelector:@selector(setDelegate:)]) [__gea_view setDelegate:__gea_obs]; [[NSNotificationCenter defaultCenter] addObserver:__gea_obs selector:@selector(textDidChange:) name:NSTextDidChangeNotification object:__gea_view]; [[NSNotificationCenter defaultCenter] addObserver:__gea_obs selector:@selector(controlTextDidChange:) name:NSControlTextDidChangeNotification object:__gea_view]; })()',
              receiverTypes,
              returnType: 'void',
            })
            continue
          }
          appendNativeMemberBinding(nativeMemberMethods, method.name, {
            emit: objcReturnExpression(method.returns, cls.framework, objcMessageSendTemplate(objcObjectExpression('{receiver}', cls.name), method.selector, method.parameters)),
            receiverTypes,
            returnType: cppType(method.returns, cls.framework),
          })
        } else {
          const params = [`${cls.wrapper} self`, ...method.parameters.map((parameter) => `${cppType(parameter.type, cls.framework)} ${parameter.name}`)]
          hostExternDeclarations[method.thunk] = bridgeDeclaration(method.thunk, cppType(method.returns, cls.framework), params.join(', '))
          appendNativeMemberBinding(nativeMemberMethods, method.name, {
            extern: method.thunk,
            receiverTypes,
            returnType: cppType(method.returns, cls.framework),
          })
        }
      }
    }
    for (const property of Object.values(cls.properties)) {
      const propertyReceiverTypes = receiverTypes.filter((receiverType) => receiverType !== 'gea_cpp_value')
      if (objcBackedFrameworks.has(cls.framework)) {
        if (
          cls.framework === 'AVFoundation' &&
          cls.name === 'AVCaptureDevice' &&
          property.name === 'virtualDeviceSwitchOverVideoZoomFactors'
        ) {
          appendNativeMemberBinding(nativeMemberPropertyGetters, property.name, {
            emit: `${property.getter}({receiver})`,
            receiverTypes: propertyReceiverTypes,
            returnType: cppType(property.type, cls.framework),
          })
          hostExternDeclarations[property.getter] = bridgeDeclaration(property.getter, cppType(property.type, cls.framework), 'gea::apple::AVFoundation::AVCaptureDevice self')
          continue
        }
        appendNativeMemberBinding(nativeMemberPropertyGetters, property.name, {
          emit: objcReturnExpression(property.type, cls.framework, `${objcObjectExpression('{receiver}', cls.name)}.${property.name}`),
          receiverTypes: propertyReceiverTypes,
          returnType: cppType(property.type, cls.framework),
        })
        if (property.setter) {
          const lhs = `${objcObjectExpression('{receiver}', cls.name)}.${property.name}`
          const rhs = objcValueExpression(property.type, cls.framework, '{value}')
          // Numeric properties are the only ones that can be ObjC NS_ENUMs (the
          // bindings model enums as `number`). C++ has no implicit int->enum
          // conversion, so e.g. `NSStackView.orientation = 1` fails to compile.
          // Cast via decltype for number-typed setters only — a no-op for
          // CGFloat, and the needed explicit cast for enum-backed properties.
          // Object/bool/string/struct setters keep their direct assignment.
          const isNumber = property.type.kind === 'primitive' && property.type.name === 'number'
          appendNativeMemberBinding(nativeMemberPropertySetters, property.name, {
            emit: isNumber ? `${lhs} = (decltype(${lhs}))(${rhs})` : `${lhs} = ${rhs}`,
            receiverTypes: propertyReceiverTypes,
            returnType: cppType(property.type, cls.framework),
          })
        }
      } else {
        hostExternDeclarations[property.getter] = bridgeDeclaration(property.getter, cppType(property.type, cls.framework), `${cls.wrapper} self`)
        appendNativeMemberBinding(nativeMemberPropertyGetters, property.name, {
          extern: property.getter,
          receiverTypes: propertyReceiverTypes,
          returnType: cppType(property.type, cls.framework),
        })
        if (!property.setter) continue
        hostExternDeclarations[property.setter] = bridgeDeclaration(property.setter, 'void', `${cls.wrapper} self, ${cppType(property.type, cls.framework)} value`)
        appendNativeMemberBinding(nativeMemberPropertySetters, property.name, {
          extern: property.setter,
          receiverTypes: propertyReceiverTypes,
          returnType: cppType(property.type, cls.framework),
        })
      }
    }
  }

  return {
    hostNamespaces,
    hostNamespaceMethods,
    embeddedHostClasses,
    nativeMemberMethods,
    nativeMemberPropertyGetters,
    nativeMemberPropertySetters,
    nativeNamespaceMethods,
    nativeTypes,
    embeddedHostFunctions,
    embeddedHostFunctionFrameworkVariants,
    embeddedHostFunctionReturnTypes,
    embeddedHostConstants,
    hostExternDeclarations,
  }
}

function receiverTypesForClass(
  cls: AppleBridgeClassMetadata,
  descendantClasses: Map<string, AppleBridgeClassMetadata[]>
): string[] {
  // 'gea_cpp_value' is load-bearing: the apple-native type model often carries
  // native wrappers as gea_cpp_value (helper params, locals, loosely-typed
  // values), and native member access must still lower for those. The downside
  // is that a plain object's field access can collide with a native member name
  // (e.g. `note.title` -> UIViewController.title); apps avoid that by not naming
  // plain-object fields after native properties.
  const candidates = [cls, ...(descendantClasses.get(`${cls.framework}.${cls.name}`) ?? [])]
  return [...new Set([...candidates.flatMap((candidate) => [candidate.name, candidate.wrapper, objcPointerType(candidate)]), 'gea_cpp_value'])]
}

function appendAppleHostConstants(target: Record<string, { emit: string; type: string }>, metadata: AppleBridgeMetadata): void {
  for (const constant of Object.values(metadata.constants ?? {})) {
    target[constant.name] = {
      emit: constantCxxExpression(constant.type, constant.value, constant.framework),
      type: constantStorageType(constant.type, constant.framework),
    }
  }
}

function constantStorageType(type: AppleTypeReference, localFramework: string): string {
  if (type.kind === 'primitive' && type.name === 'selector') return 'std::string'
  if (type.kind === 'primitive' && type.name !== 'void' && type.name !== 'boolean' && type.name !== 'number' && type.name !== 'string') {
    return 'double'
  }
  return cppType(type, localFramework)
}

function constantCxxExpression(type: AppleTypeReference, value: string | number | boolean, localFramework: string): string {
  if (type.kind === 'primitive' && (type.name === 'string' || type.name === 'selector')) {
    return `std::string(${JSON.stringify(String(value))})`
  }
  if (type.kind === 'primitive' && type.name === 'boolean') return value ? 'true' : 'false'
  if (type.kind === 'primitive' && type.name === 'number') return String(value)
  if (type.kind === 'primitive' && type.name !== 'void') return String(value)
  return `static_cast<${cppType(type, localFramework)}>(${JSON.stringify(value)})`
}

function descendantClassesByQualifiedName(metadata: AppleBridgeMetadata): Map<string, AppleBridgeClassMetadata[]> {
  const classes = Object.values(metadata.classes)
  const byName = new Map<string, AppleBridgeClassMetadata>()
  for (const cls of classes) byName.set(`${cls.framework}.${cls.name}`, cls)
  const descendants = new Map<string, AppleBridgeClassMetadata[]>()
  for (const candidate of classes) {
    let base = candidate.extends
    while (base) {
      descendants.set(base, [...(descendants.get(base) ?? []), candidate])
      base = byName.get(base)?.extends
    }
  }
  return descendants
}

function appendNativeMemberBinding(target: Record<string, NativeMemberBinding[]>, member: string, binding: NativeMemberBinding): void {
  // Bindings whose emit bridges the receiver through `.handle` can safely
  // serve a DYNAMIC (gea_cpp_value) receiver too: the boxed value carries the
  // native handle as a number and the emitter reconstructs the wrapper via
  // `NSObject{value_handle(...)}`. The compiler's matcher requires this
  // explicit opt-in so arbitrary userland objects with SDK-colliding property
  // names don't get mistaken for native controls by OTHER plugins.
  const withDynamicReceiver =
    binding.emit && binding.emit.includes('{receiver}.handle') ? { ...binding, allowDynamicReceiver: true } : binding
  target[member] = [...(target[member] ?? []), withDynamicReceiver]
}

// True when a host-thunk signature references an ObjC-only type that is guarded
// out of plain C++: the `::CMTime` / `::CLLocation…` / `::MKCoordinate…` aliases
// (declared only under `#ifdef __OBJC__`), an `NSString*`, or a bare `id`. Such a
// declaration must itself be `__OBJC__`-guarded so it drops out of the plain-C++
// translation units — the generated modules that compile as C++ never call these
// AVFoundation/CoreLocation/MapKit thunks.
function bridgeSignatureNeedsObjC(text: string): boolean {
  return /gea::apple::(CoreMedia|CoreLocation|MapKit)::|\bNSString\b|(^|[^A-Za-z0-9_])id(\b|\s)/.test(text)
}

function bridgeDeclaration(name: string, returnType: string, params: string): string[] {
  const target = cppFunctionTarget(name)
  const decl = target.namespaceName
    ? [`namespace ${target.namespaceName} {`, `${returnType} ${target.bareName}(${params});`, '}']
    : [`${returnType} ${target.bareName}(${params});`]
  if (bridgeSignatureNeedsObjC(`${returnType} ${params}`)) return ['#ifdef __OBJC__', ...decl, '#endif  // __OBJC__']
  return decl
}

function cppFunctionTarget(name: string): { namespaceName: string | null; bareName: string; qualifiedName: string } {
  const qualifiedName = name.replace(/^::/, '')
  const separator = qualifiedName.lastIndexOf('::')
  if (separator < 0) return { namespaceName: null, bareName: qualifiedName, qualifiedName }
  return {
    namespaceName: qualifiedName.slice(0, separator),
    bareName: qualifiedName.slice(separator + 2),
    qualifiedName,
  }
}

function appleBridgePreamble(
  metadata: AppleBridgeMetadata,
  programSource = '',
  options: { includeRuntime?: boolean } = {},
): string {
  const shims = createAppleHostShims(metadata)
  const declarations = Object.entries(shims.hostExternDeclarations ?? {})
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([, lines]) => lines.join('\n'))
  const overloads = appleBridgeValueArrayOverloads(metadata, shims.hostExternDeclarations ?? {}, programSource)
  return [
    options.includeRuntime === false ? '' : '#include "runtime_pch.h"',
    '#include "gea/apple/native_bridge.h"',
    ...declarations,
    ...overloads,
  ].filter(Boolean).join('\n')
}

function insertAppleBridgePreamble(source: string, preamble: string): string {
  if (source.includes('#include "gea/apple/native_bridge.h"')) return source
  if (source.startsWith('#pragma once\n')) {
    return `#pragma once\n${preamble}\n${source.slice('#pragma once\n'.length)}`
  }
  return `${preamble}\n${source}`
}

function appleBridgeValueArrayOverloads(
  metadata: AppleBridgeMetadata,
  hostExternDeclarations: Record<string, string[]>,
  programSource = ''
): string[] {
  if (!programSource.includes('std::vector<gea_cpp_value>')) return []
  const overloads: string[] = []
  let needsNumberArrayConversion = false
  const appendOverload = (
    thunk: string,
    returns: AppleTypeReference,
    localFramework: string,
    parameters: AppleParameterDefinition[]
  ) => {
    if (!hostExternDeclarations[thunk]) return
    if (!parameters.some((parameter) => isNumberArrayType(parameter.type))) return
    needsNumberArrayConversion = true
    const returnType = cppType(returns, localFramework)
    const args = parameters
      .map((parameter) => `${applePreambleParameterType(parameter.type, localFramework)} ${parameter.name}`)
      .join(', ')
    const forwarded = parameters
      .map((parameter) => (isNumberArrayType(parameter.type) ? `gea::apple::bridge::numberVectorFromValues(${parameter.name})` : parameter.name))
      .join(', ')
    const target = cppFunctionTarget(thunk)
    if (target.namespaceName) overloads.push(`namespace ${target.namespaceName} {`)
    overloads.push(`inline ${returnType} ${target.bareName}(${args}) {`)
    if (returnType === 'void') {
      overloads.push(`  ${target.bareName}(${forwarded});`)
      overloads.push('}')
    } else {
      overloads.push(`  return ${target.bareName}(${forwarded});`)
      overloads.push('}')
    }
    if (target.namespaceName) overloads.push('}')
  }

  for (const fn of Object.values(metadata.functions ?? {})) {
    appendOverload(fn.thunk, fn.returns, fn.framework, fn.parameters)
  }
  for (const cls of Object.values(metadata.classes ?? {})) {
    if (cls.constructor) appendOverload(cls.constructor.thunk, { kind: 'primitive', name: 'number' }, cls.framework, cls.constructor.parameters ?? [])
    for (const method of Object.values(cls.methods ?? {})) {
      const params = method.static ? method.parameters : [{ name: 'self', type: { kind: 'class', name: `${cls.framework}.${cls.name}` } as AppleTypeReference }, ...method.parameters]
      appendOverload(method.thunk, method.returns, cls.framework, params)
    }
  }

  if (!needsNumberArrayConversion) return []
  return [
    '',
    'namespace gea::apple::bridge {',
    'inline std::vector<double> numberVectorFromValues(const std::vector<gea_cpp_value> &values) {',
    '  std::vector<double> out;',
    '  out.reserve(values.size());',
    '  for (const auto &value : values) out.push_back(gea::runtime::coerce::to_number(value));',
    '  return out;',
    '}',
    '}',
    '',
    ...overloads,
  ]
}

function applePreambleParameterType(type: AppleTypeReference, localFramework: string): string {
  if (isNumberArrayType(type)) return 'const std::vector<gea_cpp_value> &'
  return cppType(type, localFramework)
}

function isNumberArrayType(type: AppleTypeReference): boolean {
  return type.kind === 'array' && type.element.kind === 'primitive' && type.element.name === 'number'
}

function writeAppleNativeBridgeRuntime(metadata: AppleBridgeMetadata, outDir: string): void {
  const bridgeDir = path.join(outDir, 'gea/apple')
  fs.mkdirSync(bridgeDir, { recursive: true })
  writeFileIfChanged(path.join(bridgeDir, 'native_bridge.h'), appleNativeBridgeHeader(metadata))
  writeFileIfChanged(path.join(bridgeDir, 'native_bridge.mm'), appleNativeBridgeObjCxxSource(metadata))
}

function writeFileIfChanged(filePath: string, contents: string): void {
  if (fs.existsSync(filePath) && fs.readFileSync(filePath, 'utf8') === contents) return
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, contents)
}

function appleNativeBridgeHeader(metadata: AppleBridgeMetadata): string {
  const lines = [
    '#pragma once',
    '',
    '#import <CoreGraphics/CoreGraphics.h>',
  ]
  const importedFrameworks = new Set<string>()
  for (const framework of metadata.frameworks) {
    if (objcFrameworkImports[framework.name]) importedFrameworks.add(framework.name)
  }
  // The ObjC framework umbrella headers (AppKit, Foundation, Metal, …) are
  // Objective-C: their `@interface`/`@protocol` content only parses under the
  // ObjC front-end. This header is included by BOTH the ObjC++ bridge
  // (native_bridge.mm — needs the real frameworks) AND every generated app
  // module (pure C++, which uses only the handle-based wrapper structs below and
  // never the real framework types). Guard the imports with `__OBJC__` so the
  // generated C++ modules compile without pulling — and re-parsing, per TU — the
  // entire AppKit/Metal/Foundation surface. CoreGraphics is a C header and stays
  // unguarded (its CG* structs back the C-safe `using` aliases below).
  lines.push('#ifdef __OBJC__')
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
  lines.push('#endif  // __OBJC__')
  lines.push(
    '',
    '#include <cstdint>',
    '#include <functional>',
    '#include <string>',
    '#include <type_traits>',
    '#include <vector>',
    '',
    // Forward declaration so the wrapper structs below can declare a
    // `__gea_to_value()` that converts a native wrapper into a gea_cpp_value
    // carrying its handle. The method is a template (lowered lazily), so this
    // header still compiles standalone in native_bridge.mm — which never
    // instantiates it and so never needs the full gea_cpp_value definition.
    'struct gea_cpp_value;',
    '',
    'namespace gea::apple::objc {',
    'void *object(double handle);',
    'double retain(void *object);',
    'void release(double handle);',
    // Extracts a handle from either a native wrapper (`.handle`) or a dynamic
    // gea_cpp_value (which carries the handle as its number, via __gea_to_value).
    // Lets the emitter reconstruct a native object at a member-access site whose
    // operand could be either — a typed wrapper or a value that lost its native
    // type (captured/record/array-stored, or a boxed conditional). Templated, so
    // the gea_cpp_value branch (which needs the complete runtime type) is only
    // instantiated in generated app modules, never in the runtime-free
    // native_bridge.mm.
    'template <typename __GeaT> double value_handle(const __GeaT &value) {',
    '  if constexpr (std::is_same_v<std::decay_t<__GeaT>, gea_cpp_value>) return static_cast<double>(value);',
    '  else return value.handle;',
    '}',
    '}',
    '',
  )
  if (metadata.frameworks.some((framework) => framework.name === 'Foundation')) {
    // `@class` and `NSString *` are ObjC-only; these std::string<->NSString
    // converters exist for the ObjC++ bridge. Generated C++ modules never call
    // them, so keep them out of the plain-C++ translation unit.
    lines.push(
      '#ifdef __OBJC__',
      '@class NSString;',
      'namespace gea::apple::Foundation {',
      'NSString *toNSString(const std::string &value);',
      'std::string fromNSString(NSString *value);',
      '}',
      '#endif  // __OBJC__',
      '',
    )
  }

  for (const framework of metadata.frameworks) {
    const structs = Object.values(metadata.structs).filter((entry) => entry.framework === framework.name)
    const classes = Object.values(metadata.classes).filter((entry) => entry.framework === framework.name)
    if (structs.length === 0 && classes.length === 0) continue
    lines.push(`namespace gea::apple::${framework.name} {`)
    for (const struct of structs) {
      if (nativeStructFrameworks.has(framework.name)) {
        if (framework.name === 'CoreGraphics') {
          // CoreGraphics is a C header — its ::CGRect/::CGPoint/::CGSize stay
          // visible in plain C++.
          lines.push(`using ${struct.name} = ::${struct.name};`, '')
        } else {
          // ::CLLocationCoordinate2D / ::CMTime / ::MKCoordinateSpan are only
          // declared by their ObjC framework header (guarded out in plain C++).
          // Generated C++ modules never reference these aliases (they use the
          // handle-based wrappers below), so keep them ObjC-only.
          lines.push('#ifdef __OBJC__', `using ${struct.name} = ::${struct.name};`, '#endif  // __OBJC__', '')
        }
      } else {
        lines.push(`struct ${struct.name} {`)
        for (const field of struct.fields) {
          lines.push(`  ${cppType(field.type, framework.name, true)} ${field.name}${defaultInitializer(field.type)};`)
        }
        lines.push('};', '')
      }
    }
    for (const cls of classes) {
      const base = cls.extends ? ` : ${cppType({ kind: 'class', name: cls.extends }, framework.name)}` : ''
      lines.push(`struct ${cls.name}${base} {`)
      if (cls.extends) {
        const [, baseName] = splitQualifiedName(cls.extends, framework.name)
        lines.push(`  using ${cppType({ kind: 'class', name: cls.extends }, framework.name)}::${baseName};`)
      } else {
        lines.push('  double handle = 0;')
        lines.push(`  ${cls.name}() = default;`)
        lines.push(`  explicit ${cls.name}(double rawHandle) : handle(rawHandle) {}`)
      }
      // Carry the handle when this native wrapper is stored into a gea_cpp_value
      // (record field, dynamic array element, untyped/captured variable). Routes
      // gea_cpp_key(wrapper) through the __gea_to_value overload instead of the
      // address-only catch-all, so the handle survives and round-trips back to a
      // native object at the member-access site. The return type is a *dependent*
      // template parameter (defaulting to gea_cpp_value): its completeness is
      // only checked on instantiation — in generated app modules, where
      // gea_cpp_value is complete — so native_bridge.mm, which only
      // forward-declares it and never instantiates this, still compiles.
      lines.push('  template <typename __GeaValue = gea_cpp_value> __GeaValue __gea_to_value() const { return __GeaValue(static_cast<double>(handle)); }')
      lines.push('  explicit operator bool() const { return handle != 0; }')
      lines.push('};', '')
    }
    lines.push('}', '')
  }

  appendObjCTargetBridgeDeclarations(lines, metadata)
  appendBridgeDeclarations(lines, metadata)

  return `${lines.join('\n').trimEnd()}\n`
}

function appendBridgeDeclarations(lines: string[], metadata: AppleBridgeMetadata): void {
  const declarations = createAppleHostShims(metadata).hostExternDeclarations ?? {}
  const seen = new Set<string>()
  for (const name of Object.keys(declarations).sort()) {
    const block = declarations[name]
    const signature = block.join('\n')
    if (seen.has(signature)) continue
    seen.add(signature)
    // The blocks are already `__OBJC__`-guarded at their source
    // (`bridgeDeclaration`) when their signature references an ObjC-only type,
    // so the same guarded text lands in both native_bridge.h and
    // generated_support.hpp.
    lines.push(...block)
  }
  if (seen.size > 0) lines.push('')
}

function appleNativeBridgeObjCxxSource(metadata: AppleBridgeMetadata): string {
  const importedFrameworks = new Set<string>()
  for (const framework of metadata.frameworks) {
    if (objcFrameworkImports[framework.name]) importedFrameworks.add(framework.name)
  }
  const lines = [
    '#include "gea/apple/native_bridge.h"',
    '',
    '#import <TargetConditionals.h>',
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
  appendObjCTargetBridge(lines, metadata)
  appendFoundationStringConversions(lines, metadata)
  appendDispatchBridges(lines, metadata)
  appendAVFoundationBridges(lines, metadata)
  appendPhotosBridges(lines, metadata)
  appendMetalBridges(lines, metadata)
  appendMetalKitBridges(lines, metadata)
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
  // These capture-device exposure/zoom + photo-capture APIs are
  // API_UNAVAILABLE(macos); AVFoundation.h itself exists on macOS, so the
  // header guard alone isn't enough. Exclude macOS so apple-native macOS apps
  // (which don't use the camera bridge) still compile.
  lines.push('#if __has_include(<AVFoundation/AVFoundation.h>) && !TARGET_OS_OSX')
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

// GeaAppleObjCTarget only depends on Foundation/NSObject (NOT UIKit), so it is
// emitted unconditionally on every Apple platform — macOS/AppKit builds (which
// have no UIKit) still need it for target/action callbacks.
function appendObjCTargetBridge(lines: string[], _metadata: AppleBridgeMetadata): void {
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
  // Double as a live text-change delegate: AppKit sends these selectors to an
  // NSTextField/NSTextView delegate on every edit. Declared by selector only (no
  // AppKit protocol conformance) so the shared target still compiles on UIKit,
  // where these are simply never called.
  lines.push('- (void)controlTextDidChange:(id)notification {')
  lines.push('  (void)notification;')
  lines.push('  if (_callback) _callback();')
  lines.push('}')
  lines.push('- (void)textDidChange:(id)notification {')
  lines.push('  (void)notification;')
  lines.push('  if (_callback) _callback();')
  lines.push('}')
  lines.push('@end', '')
}

function appendObjCTargetBridgeDeclarations(lines: string[], _metadata: AppleBridgeMetadata): void {
  // Pure ObjC (`@interface`, `id`, `@end`). Only referenced from ObjC++ call
  // sites (the `[[GeaAppleObjCTarget alloc] …]` callback bridge), so keep it out
  // of the plain-C++ translation unit.
  lines.push('#ifdef __OBJC__')
  lines.push('@interface GeaAppleObjCTarget : NSObject {')
  lines.push('  std::function<void()> _callback;')
  lines.push('}')
  lines.push('- (instancetype)initWithCallback:(std::function<void()>)callback;')
  lines.push('- (void)invoke:(id)sender;')
  lines.push('- (void)controlTextDidChange:(id)notification;')
  lines.push('- (void)textDidChange:(id)notification;')
  lines.push('@end')
  lines.push('#endif  // __OBJC__', '')
}

function objcPointerType(cls: AppleBridgeClassMetadata): string {
  return `${cls.name} *`
}

function objcClassReference(nativeType: string): string {
  return nativeType.startsWith('::') ? nativeType : `::${nativeType}`
}

function objcObjectExpression(value: string, nativeType: string): string {
  return `((__bridge ${objcClassReference(nativeType)} *)gea::apple::objc::object(${value}.handle))`
}

function objcAllocInitExpression(nativeType: string, selector: string, parameters: AppleParameterDefinition[]): string {
  const receiver = objcClassReference(nativeType)
  if (parameters.length === 0) return `[[${receiver} alloc] ${selector}]`
  const labels = selector.split(':').filter(Boolean)
  const segments = parameters.map((parameter, index) => `${labels[index] ?? parameter.name}: ${objcArgumentTemplate(parameter, index)}`)
  return `[[${receiver} alloc] ${segments.join(' ')}]`
}

function objcMessageSendTemplate(receiver: string, selector: string, parameters: AppleParameterDefinition[]): string {
  const objcReceiver = /^[A-Za-z_][A-Za-z0-9_]*$/.test(receiver) ? objcClassReference(receiver) : receiver
  if (parameters.length === 0) return `[${objcReceiver} ${selector}]`
  const labels = selector.split(':').filter(Boolean)
  const segments = parameters.map((parameter, index) => `${labels[index] ?? parameter.name}: ${objcArgumentTemplate(parameter, index)}`)
  return `[${objcReceiver} ${segments.join(' ')}]`
}

function objcArgumentTemplate(parameter: AppleParameterDefinition, index: number): string {
  return objcValueExpression(parameter.type, '', `{arg${index}}`)
}

function objcValueExpression(type: AppleTypeReference, localFramework: string, value: string): string {
  if (type.kind === 'function') return objcBlockExpression(type, localFramework, value)
  if (type.kind === 'array') return value
  if (type.kind === 'class') {
    const [, nativeType] = splitQualifiedName(type.name, localFramework)
    return objcObjectExpression(value, nativeType)
  }
  if (type.kind === 'primitive' && type.name === 'string') return `gea::apple::Foundation::toNSString(${value})`
  if (type.kind === 'primitive' && type.name === 'selector') return `NSSelectorFromString(gea::apple::Foundation::toNSString(${value}))`
  if (
    type.kind === 'primitive' &&
    type.name !== 'void' &&
    type.name !== 'boolean' &&
    type.name !== 'number'
  ) {
    return `static_cast<${type.name}>(gea::runtime::coerce::to_number(${value}))`
  }
  return value
}

function objcBlockExpression(type: AppleTypeReference & { kind: 'function' }, localFramework: string, value: string): string {
  const parameters = type.parameters ?? []
  const signature = parameters.map((parameter, index) => `${objcBlockParameterType(parameter.type, localFramework)} __gea_arg${index}`).join(', ')
  const args = parameters.map((parameter, index) => cppValueFromObjCBlockParameter(parameter.type, localFramework, `__gea_arg${index}`)).join(', ')
  const invoke = type.returns.kind === 'primitive' && type.returns.name === 'void'
    ? `if (__gea_handler) __gea_handler(${args});`
    : `if (__gea_handler) return ${objcValueExpression(type.returns, localFramework, `__gea_handler(${args})`)}; return ${objcDefaultValue(type.returns)};`
  return `([&]() { auto __gea_handler = ${cppType(type, localFramework)}(${value}); return ^${signature ? `(${signature})` : ''} { ${invoke} }; })()`
}

function objcBlockParameterType(type: AppleTypeReference, localFramework: string): string {
  if (type.kind === 'class') {
    const [, nativeType] = splitQualifiedName(type.name, localFramework)
    return `${objcClassReference(nativeType)} *`
  }
  if (type.kind === 'struct') return cppType(type, localFramework)
  if (type.kind === 'primitive') {
    if (type.name === 'boolean') return 'BOOL'
    if (type.name === 'number') return 'double'
    if (type.name === 'string') return 'NSString *'
    if (type.name === 'selector') return 'SEL'
    if (type.name === 'void') return 'void'
    return type.name
  }
  return 'id'
}

function cppValueFromObjCBlockParameter(type: AppleTypeReference, localFramework: string, value: string): string {
  if (type.kind === 'class') {
    const [, nativeType] = splitQualifiedName(type.name, localFramework)
    return `${cppType(type, localFramework)}(gea::apple::objc::retain((__bridge void *)(${objcClassReference(nativeType)} *)${value}))`
  }
  if (type.kind === 'primitive' && type.name === 'string') return `gea::apple::Foundation::fromNSString(${value})`
  if (type.kind === 'primitive' && type.name === 'boolean') return `${value} != NO`
  return value
}

function objcDefaultValue(type: AppleTypeReference): string {
  if (type.kind === 'class' || type.kind === 'array') return 'nil'
  if (type.kind === 'function') return 'nil'
  if (type.kind === 'primitive') {
    if (type.name === 'void') return ''
    if (type.name === 'boolean') return 'NO'
    if (type.name === 'string') return 'nil'
    if (type.name === 'selector') return 'nullptr'
    if (type.name === 'number') return '0'
    return `static_cast<${type.name}>(0)`
  }
  return 'nil'
}

function objcReturnExpression(type: AppleTypeReference, localFramework: string, expression: string): string {
  if (type.kind === 'primitive' && type.name === 'void') return expression
  if (type.kind === 'class') {
    const [, nativeType] = splitQualifiedName(type.name, localFramework)
    return `${cppType(type, localFramework)}(gea::apple::objc::retain((__bridge void *)(${objcClassReference(nativeType)} *)${expression}))`
  }
  if (type.kind === 'primitive' && type.name === 'string') return `gea::apple::Foundation::fromNSString(${expression})`
  return expression
}

function defaultInitializer(type: AppleTypeReference): string {
  if (type.kind === 'array') return ''
  if (type.kind !== 'primitive') return ''
  if (type.name === 'number') return ' = 0'
  if (type.name === 'boolean') return ' = false'
  return ''
}

function loadMetadata(metadataPath: string | undefined, entry: string): AppleBridgeMetadata | null {
  if (!metadataPath) return null
  const resolved = path.resolve(path.dirname(entry), metadataPath)
  return JSON.parse(fs.readFileSync(resolved, 'utf8')) as AppleBridgeMetadata
}

function cppType(type: AppleTypeReference, localFramework: string, preferLocalNames = false): string {
  if (type.kind === 'function') {
    const returns = cppType(type.returns, localFramework, preferLocalNames)
    const params = (type.parameters ?? []).map((parameter) => cppType(parameter.type, localFramework, preferLocalNames)).join(', ')
    return `std::function<${returns}(${params})>`
  }
  if (type.kind === 'array') {
    return `std::vector<${cppType(type.element, localFramework, preferLocalNames)}>`
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
  if (preferLocalNames && framework === localFramework) return name
  return `gea::apple::${framework}::${name}`
}

function splitQualifiedName(name: string, fallbackFramework: string): [string, string] {
  const dot = name.indexOf('.')
  if (dot < 0) return [fallbackFramework, name]
  return [name.slice(0, dot), name.slice(dot + 1)]
}

export default appleNativePlugin

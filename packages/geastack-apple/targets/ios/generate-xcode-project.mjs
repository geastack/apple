#!/usr/bin/env node
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { execFileSync } from 'node:child_process'

// The project is the directory this ran in -- the one being compiled, which is
// also what the CLI resolves from cwd. iOS target sources live next to this
// script, not in the project. App metadata and icon generation come from the
// gea CLI (build-ios.sh resolves it and passes $GEA_CLI_BIN).
const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const projectDir = process.cwd()
const geaCli = process.env.GEA_CLI_BIN || path.join(scriptDir, '../../node_modules/@geastack/cli/bin/gea.mjs')
function gea(args) {
  return execFileSync(process.execPath, [geaCli, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] })
}

const args = process.argv.slice(2)

function opt(name) {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : ''
}

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

const appId = opt('--app-id')
const appName = opt('--app-name')
const bundleId = opt('--bundle-id')
const generatedDir = path.resolve(opt('--generated-dir'))
const projectPath = path.resolve(opt('--project-path'))

if (!appId || !appName || !bundleId || !generatedDir || !projectPath) {
  fail('usage: generate-xcode-project.mjs --app-id <id> --app-name <name> --bundle-id <id> --generated-dir <path> --project-path <path>  (run from the app directory)')
}

const iosDir = scriptDir  // apple/targets/ios — this script's own directory, not the apps repo
// The framework packages are wherever build-ios.sh resolved them (the app's
// hoisted node_modules, or a linked checkout); it exports the roots it found.
const geaCore = process.env.GEA_CORE || ''
if (!geaCore) fail('GEA_CORE is not set: run this generator through build-ios.sh, which resolves @geastack/core for it.')
const plistOut = path.join(projectPath, 'Info.plist')
let appMeta
try {
  appMeta = JSON.parse(gea(['apps', 'inspect', appId, '--json']))
} catch {
  fail(`Unknown app id: ${appId}`)
}
// `apps inspect` reports an absolute directory; there is nothing to join it to.
const appRoot = appMeta.root
const appIconAssetsDir = path.join(generatedDir, 'Assets.xcassets')

// Omit the app-icon asset catalog when GEA_IOS_SKIP_APP_ICON=1. actool refuses to
// compile a catalog unless an installed simulator runtime's build matches the SDK
// exactly (e.g. SDK 23F81a needs a 23F81a runtime, not a 23F73 one) — a skew that
// blocks otherwise-fine builds. Skipping it yields an app with the default icon.
const skipAppIcon = process.env.GEA_IOS_SKIP_APP_ICON === '1'

fs.rmSync(projectPath, { recursive: true, force: true })
fs.mkdirSync(path.join(projectPath, 'project.xcworkspace'), { recursive: true })
fs.mkdirSync(path.join(projectPath, 'xcshareddata/xcschemes'), { recursive: true })
if (!skipAppIcon) gea(['apps', 'apple-icons', appId, '--platform', 'ios', '--assets-dir', appIconAssetsDir])

const plistTemplate = fs.readFileSync(path.join(iosDir, 'Info.plist.in'), 'utf8')
fs.writeFileSync(
  plistOut,
  plistTemplate
    .replaceAll('@APP_EXEC@', appName)
    .replaceAll('@APP_NAME@', appName)
    .replaceAll('@BUNDLE_ID@', bundleId),
)

function id(label) {
  return crypto.createHash('sha1').update(label).digest('hex').slice(0, 24).toUpperCase()
}

function q(value) {
  return `"${String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`
}

function rel(file) {
  return path.relative(projectDir, file).replaceAll(path.sep, '/')
}

function source(file, kind = 'sourcecode.cpp.cpp') {
  return { file: path.resolve(file), kind }
}

function resource(file, kind = 'file') {
  return { file: path.resolve(file), kind }
}

function existing(entry) {
  return fs.existsSync(entry.file)
}

function readGeatscSources(dir, kind = 'sourcecode.cpp.cpp') {
  const sourceList = path.join(dir, 'geatsc-sources.txt')
  if (!fs.existsSync(sourceList)) return []
  return fs.readFileSync(sourceList, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((file) => source(file, kind))
    .filter(existing)
}

function nativeSourceKind(file) {
  if (/\.mm$/i.test(file)) return 'sourcecode.cpp.objcpp'
  if (/\.m$/i.test(file)) return 'sourcecode.c.objc'
  if (/\.c$/i.test(file)) return 'sourcecode.c.c'
  return 'sourcecode.cpp.cpp'
}

function findAppNativeSources() {
  const dir = path.join(appRoot, 'ios')
  if (!fs.existsSync(dir)) return []
  const out = []
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const file = path.join(current, entry.name)
      if (entry.isDirectory()) {
        visit(file)
      } else if (entry.isFile() && /\.(c|cc|cpp|m|mm)$/i.test(entry.name)) {
        out.push(source(file, nativeSourceKind(file)))
      }
    }
  }
  visit(dir)
  return out.sort((a, b) => a.file.localeCompare(b.file))
}

function findFontResources() {
  const fontDir = path.join(projectDir, 'assets/fonts')
  if (!fs.existsSync(fontDir)) return []
  return fs.readdirSync(fontDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /\.(ttf|otf)$/i.test(entry.name))
    .map((entry) => path.join(fontDir, entry.name))
    .sort()
}

const appleNativeBridgeSource = source(path.join(generatedDir, 'gea/apple/native_bridge.mm'), 'sourcecode.cpp.objcpp')
const generatedProgramSources = readGeatscSources(
  generatedDir,
  existing(appleNativeBridgeSource) ? 'sourcecode.cpp.objcpp' : 'sourcecode.cpp.cpp',
)
const rendererSources = [
  'ios_renderer.mm',
  'renderer/ios_renderer_support.mm',
  'renderer/native_label.mm',
  'renderer/native_button.mm',
  'renderer/native_scroll_container.mm',
  'renderer/view_reconciler.mm',
].map((file) => source(path.join(iosDir, 'main', file), 'sourcecode.cpp.objcpp'))
const appNativeSources = findAppNativeSources()
const sources = [
  source(path.join(iosDir, 'main/ios_main.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_root_background.cpp')),
  ...rendererSources,
  source(path.join(iosDir, 'main/canvas_view.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/color_convert.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/image_bridge.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/font_registry.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/press_bridge.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_display.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_timers.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_app_platform.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_memory.cpp')),
  // gea::platform::audio — the AVAudioEngine backend, shared verbatim with macOS.
  source(path.join(iosDir, '../shared/apple_audio.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_sensors.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_camera.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosDir, 'main/ios_apps.c'), 'sourcecode.c.c'),
  ...appNativeSources,
  // Framework C/C++ sources come from @geastack/core/gea_sources.sh,
  // passed by build-ios.sh via env (iOS-curated: camera kept since ios_camera.mm
  // provides it; OTA/diagnostics services + the single-app runtime
  // shell excluded — iOS uses its own UIKit run loop). Single source of truth.
  ...(process.env.GEA_FW_C_SOURCES || '').split('\n').filter(Boolean).map((f) => source(f, 'sourcecode.c.c')),
  ...(process.env.GEA_FW_CXX_SOURCES || '').split('\n').filter(Boolean).map((f) => source(f)),
  // gea_app_entry.cpp provides Application::init/frame, which calls the one
  // __gea_top_level geatsc emitted (deliberately not in the manifest).
  source(path.join(geaCore, 'gea_app_entry.cpp')),
  ...generatedProgramSources,
  appleNativeBridgeSource,
].filter(existing)

const fontGenerated = source(path.join(generatedDir, 'gea_embedded_font_generated.cpp'))
if (existing(fontGenerated)) sources.push(fontGenerated)
const assetsGenerated = source(path.join(generatedDir, 'gea_embedded_assets_generated.cpp'))
if (existing(assetsGenerated)) sources.push(assetsGenerated)
const hasGeneratedFonts = sources.some((entry) => path.basename(entry.file) === 'gea_embedded_font_generated.cpp')

const fontResources = findFontResources().map((file) => resource(file))
const appIconAssets = resource(appIconAssetsDir, 'folder.assetcatalog')
const appIconResources = skipAppIcon ? [] : [appIconAssets]
const uiTestSource = source(path.join(iosDir, 'test/GeaIosRubberBandUITests.swift'), 'sourcecode.swift')
const uiTestSources = existing(uiTestSource) ? [uiTestSource] : []
const hasUiTests = uiTestSources.length > 0

const frameworks = [
  'UIKit.framework',
  'QuartzCore.framework',
  'CoreGraphics.framework',
  'CoreText.framework',
  'CoreMotion.framework',
  'CoreLocation.framework',
  'CoreMedia.framework',
  'CoreVideo.framework',
  'ImageIO.framework',
  'MapKit.framework',
  'AVFoundation.framework',
  'Photos.framework',
  'Metal.framework',
  'MetalKit.framework',
  'Foundation.framework',
]

const productId = id('product')
const targetId = id('target')
const projectId = id('project')
const mainGroupId = id('group-main')
const productGroupId = id('group-products')
const sourcesPhaseId = id('phase-sources')
const frameworksPhaseId = id('phase-frameworks')
const resourcesPhaseId = id('phase-resources')
const configListProjectId = id('configs-project')
const configListTargetId = id('configs-target')
const debugProjectId = id('debug-project')
const releaseProjectId = id('release-project')
const debugTargetId = id('debug-target')
const releaseTargetId = id('release-target')
const uiTestProductId = id('product-ui-tests')
const uiTestTargetId = id('target-ui-tests')
const uiTestSourcesPhaseId = id('phase-ui-test-sources')
const uiTestFrameworksPhaseId = id('phase-ui-test-frameworks')
const uiTestConfigListId = id('configs-ui-test-target')
const uiTestDebugId = id('debug-ui-test-target')
const uiTestReleaseId = id('release-ui-test-target')
const uiTestDependencyId = id('dependency-ui-test-app')
const uiTestProxyId = id('proxy-ui-test-app')

const fileRefs = []
const buildFiles = []

for (const s of sources) {
  const label = rel(s.file)
  const compilerSettings = s.kind === 'sourcecode.cpp.objcpp'
    ? ' settings = {COMPILER_FLAGS = "-fobjc-exceptions"; };'
    : ''
  fileRefs.push(`${id(`file:${label}`)} /* ${path.basename(s.file)} */ = {isa = PBXFileReference; lastKnownFileType = ${s.kind}; path = ${q(s.file)}; sourceTree = "<absolute>"; };`)
  buildFiles.push(`${id(`build:${label}`)} /* ${path.basename(s.file)} in Sources */ = {isa = PBXBuildFile; fileRef = ${id(`file:${label}`)} /* ${path.basename(s.file)} */;${compilerSettings} };`)
}

for (const r of fontResources) {
  const label = rel(r.file)
  fileRefs.push(`${id(`file:${label}`)} /* ${path.basename(r.file)} */ = {isa = PBXFileReference; lastKnownFileType = ${r.kind}; path = ${q(r.file)}; sourceTree = "<absolute>"; };`)
  buildFiles.push(`${id(`build:${label}`)} /* ${path.basename(r.file)} in Resources */ = {isa = PBXBuildFile; fileRef = ${id(`file:${label}`)} /* ${path.basename(r.file)} */; };`)
}

for (const a of appIconResources) {
  const label = rel(a.file)
  fileRefs.push(`${id(`file:${label}`)} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = ${a.kind}; path = ${q(a.file)}; sourceTree = "<absolute>"; };`)
  buildFiles.push(`${id(`build:${label}`)} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${id(`file:${label}`)} /* Assets.xcassets */; };`)
}

for (const fw of frameworks) {
  fileRefs.push(`${id(`file:${fw}`)} /* ${fw} */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = ${fw}; path = System/Library/Frameworks/${fw}; sourceTree = SDKROOT; };`)
  buildFiles.push(`${id(`build:${fw}`)} /* ${fw} in Frameworks */ = {isa = PBXBuildFile; fileRef = ${id(`file:${fw}`)} /* ${fw} */; };`)
}

for (const s of uiTestSources) {
  const label = rel(s.file)
  fileRefs.push(`${id(`file:${label}`)} /* ${path.basename(s.file)} */ = {isa = PBXFileReference; lastKnownFileType = ${s.kind}; path = ${q(s.file)}; sourceTree = "<absolute>"; };`)
  buildFiles.push(`${id(`build:${label}`)} /* ${path.basename(s.file)} in Sources */ = {isa = PBXBuildFile; fileRef = ${id(`file:${label}`)} /* ${path.basename(s.file)} */; };`)
}
if (hasUiTests) {
  fileRefs.push(`${id('file:XCTest.framework')} /* XCTest.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = System/Library/Frameworks/XCTest.framework; sourceTree = SDKROOT; };`)
  buildFiles.push(`${id('build:XCTest.framework')} /* XCTest.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${id('file:XCTest.framework')} /* XCTest.framework */; };`)
}

const productRef = `${productId} /* ${appName}.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ${q(`${appName}.app`)}; sourceTree = BUILT_PRODUCTS_DIR; };`
const uiTestProductRef = hasUiTests
  ? `${uiTestProductId} /* GeaIosRubberBandUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GeaIosRubberBandUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };`
  : ''
const includePaths = [
  path.join(iosDir, 'main'),
  generatedDir,
  path.join(appRoot, 'ios'),
  // Framework include roots (core/host/engine includes + vendor/stb + AnimatedGIF)
  // from the shared manifest gea_sources.sh, passed by build-ios.sh via env.
  ...(process.env.GEA_FW_INCLUDE_DIRS || '').split('\n').filter(Boolean),
]

function buildSettings(configuration) {
  const preprocessorDefinitions = [
    'GEA_EMBEDDED_GIF_C_API=1',
    'GEA_EMBEDDED_ENABLE_NATIVE_TEXT_INPUT=1',
    'GEA_EMBEDDED_ENABLE_VIRTUAL_KEYBOARD=0',
    'GEA_CPP_USE_TO_CHARS_DOUBLE=0',
    'GEA_CPP_USE_FROM_CHARS_DOUBLE=0',
    // iOS renders full colour: pixel::native_t is RGBA8888 (32-bit), not RGB565.
    // 1 == GEA_PIXEL_RGBA8888 (see pixel.h). The Canvas engine, the primary
    // display path (ios_display.mm's uint32 framebuffer → gea_ios_display_presented_pixels),
    // and the shared text/canvas-store/camera paths all operate on the 32-bit
    // native pixel with no runtime format branch and no colour conversion.
    'GEA_EMBEDDED_PIXEL_FORMAT=1',
    ...(hasGeneratedFonts ? ['GEA_EMBEDDED_HAS_GENERATED_FONTS=1'] : []),
  ]
  return `{
				ALWAYS_SEARCH_USER_PATHS = NO;${skipAppIcon ? '' : `
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`}
				CLANG_CXX_LANGUAGE_STANDARD = "c++20";
				CLANG_CXX_LIBRARY = "libc++";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEFINES_MODULE = NO;
				GCC_ENABLE_OBJC_EXCEPTIONS = YES;
				GCC_PREPROCESSOR_DEFINITIONS = (${preprocessorDefinitions.map(q).join(', ')});
				HEADER_SEARCH_PATHS = (${includePaths.map(q).join(', ')});
				INFOPLIST_FILE = ${q(plistOut)};
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				ONLY_ACTIVE_ARCH = ${configuration === 'Debug' ? 'YES' : 'NO'};
				PRODUCT_BUNDLE_IDENTIFIER = ${q(bundleId)};
				PRODUCT_NAME = ${q(appName)};
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = "1,2";
			}`
}

function uiTestBuildSettings(configuration) {
  return `{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
				ONLY_ACTIVE_ARCH = ${configuration === 'Debug' ? 'YES' : 'NO'};
				PRODUCT_BUNDLE_IDENTIFIER = ${q(`${bundleId}.rubber-band-ui-tests`)};
				PRODUCT_MODULE_NAME = GeaIosRubberBandUITests;
				PRODUCT_NAME = GeaIosRubberBandUITests;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = GeaIos;
			}`
}

const sourceChildren = sources.map((s) => `${id(`file:${rel(s.file)}`)} /* ${path.basename(s.file)} */`)
const uiTestSourceChildren = uiTestSources.map((s) => `${id(`file:${rel(s.file)}`)} /* ${path.basename(s.file)} */`)
const resourceChildren = [
  ...fontResources.map((r) => `${id(`file:${rel(r.file)}`)} /* ${path.basename(r.file)} */`),
  ...appIconResources.map((a) => `${id(`file:${rel(a.file)}`)} /* Assets.xcassets */`),
]
const frameworkChildren = frameworks.map((fw) => `${id(`file:${fw}`)} /* ${fw} */`)
const mainGroupChildren = [
  ...sourceChildren,
  ...uiTestSourceChildren,
  ...resourceChildren,
  ...frameworkChildren,
  ...(hasUiTests ? [`${id('file:XCTest.framework')} /* XCTest.framework */`] : []),
  `${productGroupId} /* Products */`,
]
const sourceBuildRefs = sources.map((s) => `${id(`build:${rel(s.file)}`)} /* ${path.basename(s.file)} in Sources */`)
const uiTestSourceBuildRefs = uiTestSources.map((s) => `${id(`build:${rel(s.file)}`)} /* ${path.basename(s.file)} in Sources */`)
const resourceBuildRefs = [
  ...fontResources.map((r) => `${id(`build:${rel(r.file)}`)} /* ${path.basename(r.file)} in Resources */`),
  ...appIconResources.map((a) => `${id(`build:${rel(a.file)}`)} /* Assets.xcassets in Resources */`),
]
const frameworkBuildRefs = frameworks.map((fw) => `${id(`build:${fw}`)} /* ${fw} in Frameworks */`)
const uiTestFrameworkBuildRefs = hasUiTests ? [`${id('build:XCTest.framework')} /* XCTest.framework in Frameworks */`] : []

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		${buildFiles.join('\n\t\t')}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		${fileRefs.join('\n\t\t')}
		${productRef}
		${uiTestProductRef}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${frameworksPhaseId} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (${frameworkBuildRefs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };
		${hasUiTests ? `${uiTestFrameworksPhaseId} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (${uiTestFrameworkBuildRefs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };` : ''}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${mainGroupId} = {isa = PBXGroup; children = (${mainGroupChildren.join(', ')}); sourceTree = "<group>"; };
		${productGroupId} = {isa = PBXGroup; children = (${[`${productId} /* ${appName}.app */`, ...(hasUiTests ? [`${uiTestProductId} /* GeaIosRubberBandUITests.xctest */`] : [])].join(', ')}); name = Products; sourceTree = "<group>"; };
/* End PBXGroup section */

${hasUiTests ? `/* Begin PBXContainerItemProxy section */
		${uiTestProxyId} = {isa = PBXContainerItemProxy; containerPortal = ${projectId} /* Project object */; proxyType = 1; remoteGlobalIDString = ${targetId}; remoteInfo = GeaIos; };
/* End PBXContainerItemProxy section */` : ''}

/* Begin PBXNativeTarget section */
		${targetId} = {isa = PBXNativeTarget; buildConfigurationList = ${configListTargetId}; buildPhases = (${sourcesPhaseId}, ${frameworksPhaseId}, ${resourcesPhaseId}); buildRules = (); dependencies = (); name = GeaIos; productName = ${q(appName)}; productReference = ${productId} /* ${appName}.app */; productType = "com.apple.product-type.application"; };
		${hasUiTests ? `${uiTestTargetId} = {isa = PBXNativeTarget; buildConfigurationList = ${uiTestConfigListId}; buildPhases = (${uiTestSourcesPhaseId}, ${uiTestFrameworksPhaseId}); buildRules = (); dependencies = (${uiTestDependencyId}); name = GeaIosRubberBandUITests; productName = GeaIosRubberBandUITests; productReference = ${uiTestProductId} /* GeaIosRubberBandUITests.xctest */; productType = "com.apple.product-type.bundle.ui-testing"; };` : ''}
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${projectId} = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600; TargetAttributes = {${targetId} = {CreatedOnToolsVersion = 16.0;};${hasUiTests ? ` ${uiTestTargetId} = {CreatedOnToolsVersion = 16.0; TestTargetID = ${targetId};};` : ''}};}; buildConfigurationList = ${configListProjectId}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = ${mainGroupId}; productRefGroup = ${productGroupId}; projectDirPath = ""; projectRoot = ""; targets = (${[targetId, ...(hasUiTests ? [uiTestTargetId] : [])].join(', ')}); };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${resourcesPhaseId} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${resourceBuildRefs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${sourcesPhaseId} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${sourceBuildRefs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };
		${hasUiTests ? `${uiTestSourcesPhaseId} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${uiTestSourceBuildRefs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };` : ''}
/* End PBXSourcesBuildPhase section */

${hasUiTests ? `/* Begin PBXTargetDependency section */
		${uiTestDependencyId} = {isa = PBXTargetDependency; target = ${targetId} /* GeaIos */; targetProxy = ${uiTestProxyId}; };
/* End PBXTargetDependency section */` : ''}

/* Begin XCBuildConfiguration section */
		${debugProjectId} = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
		${releaseProjectId} = {isa = XCBuildConfiguration; buildSettings = {}; name = Release; };
		${debugTargetId} = {isa = XCBuildConfiguration; buildSettings = ${buildSettings('Debug')}; name = Debug; };
		${releaseTargetId} = {isa = XCBuildConfiguration; buildSettings = ${buildSettings('Release')}; name = Release; };
		${hasUiTests ? `${uiTestDebugId} = {isa = XCBuildConfiguration; buildSettings = ${uiTestBuildSettings('Debug')}; name = Debug; };
		${uiTestReleaseId} = {isa = XCBuildConfiguration; buildSettings = ${uiTestBuildSettings('Release')}; name = Release; };` : ''}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${configListProjectId} = {isa = XCConfigurationList; buildConfigurations = (${debugProjectId}, ${releaseProjectId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
		${configListTargetId} = {isa = XCConfigurationList; buildConfigurations = (${debugTargetId}, ${releaseTargetId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
		${hasUiTests ? `${uiTestConfigListId} = {isa = XCConfigurationList; buildConfigurations = (${uiTestDebugId}, ${uiTestReleaseId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };` : ''}
/* End XCConfigurationList section */
	};
	rootObject = ${projectId};
}
`

const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES" buildArchitectures="Automatic">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${targetId}" BuildableName="${appName}.app" BlueprintName="GeaIos" ReferencedContainer="container:GeaIos.xcodeproj"/>
      </BuildActionEntry>
      ${hasUiTests ? `<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${uiTestTargetId}" BuildableName="GeaIosRubberBandUITests.xctest" BlueprintName="GeaIosRubberBandUITests" ReferencedContainer="container:GeaIos.xcodeproj"/>
      </BuildActionEntry>` : ''}
    </BuildActionEntries>
  </BuildAction>
  ${hasUiTests ? `<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES">
    <Testables>
      <TestableReference skipped="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${uiTestTargetId}" BuildableName="GeaIosRubberBandUITests.xctest" BlueprintName="GeaIosRubberBandUITests" ReferencedContainer="container:GeaIos.xcodeproj"/>
      </TestableReference>
    </Testables>
    <MacroExpansion>
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${targetId}" BuildableName="${appName}.app" BlueprintName="GeaIos" ReferencedContainer="container:GeaIos.xcodeproj"/>
    </MacroExpansion>
  </TestAction>` : ''}
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${targetId}" BuildableName="${appName}.app" BlueprintName="GeaIos" ReferencedContainer="container:GeaIos.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${targetId}" BuildableName="${appName}.app" BlueprintName="GeaIos" ReferencedContainer="container:GeaIos.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`

fs.writeFileSync(path.join(projectPath, 'project.pbxproj'), pbxproj)
fs.writeFileSync(
  path.join(projectPath, 'project.xcworkspace/contents.xcworkspacedata'),
  '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n',
)
fs.writeFileSync(path.join(projectPath, 'xcshareddata/xcschemes/GeaIos.xcscheme'), scheme)
console.log(`Generated ${projectPath}`)

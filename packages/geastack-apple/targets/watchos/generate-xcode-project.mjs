#!/usr/bin/env node
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { execFileSync } from 'node:child_process'

// Generates a single-target, watch-only watchOS app project (WKWatchOnly): a
// SwiftUI shell plus the gea runtime compiled from C++. It mirrors the iOS
// generator next door -- same source manifest, same generated program -- but
// renders through the framebuffer only, since watchOS has no UIView tree.
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
const displayName = opt('--display-name') || appName
const bundleId = opt('--bundle-id')
const cssDevicePixelRatio = Number(opt('--css-device-pixel-ratio') || 1.5)
const generatedDir = path.resolve(opt('--generated-dir'))
const projectPath = path.resolve(opt('--project-path'))

if (!appId || !appName || !bundleId || !generatedDir || !projectPath || !(cssDevicePixelRatio > 0)) {
  fail('usage: generate-xcode-project.mjs --app-id <id> --app-name <name> [--display-name <name>] --bundle-id <id> [--css-device-pixel-ratio <r>] --generated-dir <path> --project-path <path>  (run from the app directory)')
}

const watchDir = scriptDir
const iosMainDir = path.join(scriptDir, '../ios/main')
const geaCore = process.env.GEA_CORE || ''
if (!geaCore) fail('GEA_CORE is not set: run this generator through build-watchos.sh, which resolves @geastack/core for it.')
const plistOut = path.join(projectPath, 'Info.plist')
let appMeta
try {
  appMeta = JSON.parse(gea(['apps', 'inspect', appId, '--json']))
} catch {
  fail(`Unknown app id: ${appId}`)
}
const appRoot = appMeta.root
const appIconAssetsDir = path.join(generatedDir, 'Assets.xcassets')

// Same escape hatch as iOS: actool refuses a catalog when no installed
// simulator runtime matches the SDK build exactly.
let hasAppIcon = process.env.GEA_WATCHOS_SKIP_APP_ICON !== '1'

fs.rmSync(projectPath, { recursive: true, force: true })
fs.mkdirSync(path.join(projectPath, 'project.xcworkspace'), { recursive: true })
fs.mkdirSync(path.join(projectPath, 'xcshareddata/xcschemes'), { recursive: true })

// Many example apps declare no icon. A missing icon is not a reason to refuse
// the build: the app gets the system's default icon instead.
if (hasAppIcon) {
  try {
    gea(['apps', 'apple-icons', appId, '--platform', 'watchos', '--assets-dir', appIconAssetsDir])
  } catch {
    process.stderr.write(`No app icon for ${appId}; building with the default icon.\n`)
    hasAppIcon = false
  }
}

const plistTemplate = fs.readFileSync(path.join(watchDir, 'Info.plist.in'), 'utf8')
fs.writeFileSync(
  plistOut,
  plistTemplate
    .replaceAll('@APP_EXEC@', appName)
    .replaceAll('@APP_NAME@', appName)
    .replaceAll('@APP_DISPLAY_NAME@', displayName.replaceAll('&', '&amp;').replaceAll('<', '&lt;'))
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

function existing(entry) {
  return fs.existsSync(entry.file)
}

function readGeatscSources(dir) {
  const sourceList = path.join(dir, 'geatsc-sources.txt')
  if (!fs.existsSync(sourceList)) return []
  return fs.readFileSync(sourceList, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((file) => source(file))
    .filter(existing)
}

function nativeSourceKind(file) {
  if (/\.mm$/i.test(file)) return 'sourcecode.cpp.objcpp'
  if (/\.m$/i.test(file)) return 'sourcecode.c.objc'
  if (/\.c$/i.test(file)) return 'sourcecode.c.c'
  return 'sourcecode.cpp.cpp'
}

// An app's own native code for this target lives in <app>/watchos, the way
// iOS-only code lives in <app>/ios.
function findAppNativeSources() {
  const dir = path.join(appRoot, 'watchos')
  if (!fs.existsSync(dir)) return []
  const out = []
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const file = path.join(current, entry.name)
      if (entry.isDirectory()) visit(file)
      else if (entry.isFile() && /\.(c|cc|cpp|m|mm)$/i.test(entry.name)) out.push(source(file, nativeSourceKind(file)))
    }
  }
  visit(dir)
  return out.sort((a, b) => a.file.localeCompare(b.file))
}

const sources = [
  source(path.join(watchDir, 'main/watchos_app.swift'), 'sourcecode.swift'),
  source(path.join(watchDir, 'main/watchos_host.mm'), 'sourcecode.cpp.objcpp'),
  // Camera-less camera backend, plus battery and haptics through WatchKit.
  source(path.join(watchDir, 'main/watchos_platform.mm'), 'sourcecode.cpp.objcpp'),
  // Platform backends shared verbatim with iOS: the RGBA8888 framebuffer, the
  // frame clock, allocator, app registry, touch state
  // plus CoreMotion, and the AVAudioEngine audio backend.
  source(path.join(iosMainDir, 'ios_display.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosMainDir, 'ios_timers.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(iosMainDir, 'ios_memory.cpp')),
  source(path.join(iosMainDir, 'ios_apps.c'), 'sourcecode.c.c'),
  source(path.join(iosMainDir, 'ios_sensors.mm'), 'sourcecode.cpp.objcpp'),
  source(path.join(watchDir, '../shared/apple_audio.mm'), 'sourcecode.cpp.objcpp'),
  ...findAppNativeSources(),
  // Framework sources from @geastack/core/gea_sources.sh, curated by
  // build-watchos.sh (no services or single-app runtime shell).
  ...(process.env.GEA_FW_C_SOURCES || '').split('\n').filter(Boolean).map((f) => source(f, 'sourcecode.c.c')),
  ...(process.env.GEA_FW_CXX_SOURCES || '').split('\n').filter(Boolean).map((f) => source(f)),
  // Application::init/frame, which call the __gea_top_level geatsc emitted.
  source(path.join(geaCore, 'gea_app_entry.cpp')),
  ...readGeatscSources(generatedDir),
  source(path.join(generatedDir, 'gea_embedded_font_generated.cpp')),
  source(path.join(generatedDir, 'gea_embedded_assets_generated.cpp')),
].filter(existing)
const hasGeneratedFonts = sources.some((entry) => path.basename(entry.file) === 'gea_embedded_font_generated.cpp')

const resources = hasAppIcon ? [{ file: appIconAssetsDir, kind: 'folder.assetcatalog' }] : []
const frameworks = [
  'SwiftUI.framework',
  'WatchKit.framework',
  'UIKit.framework',
  'CoreGraphics.framework',
  'CoreMotion.framework',
  'AVFoundation.framework',
  'Foundation.framework',
]

// The UI test lives under test/, which the npm package leaves out, so only a
// checkout of this repo gets the target (as with the iOS rubber-band test).
const uiTestSource = source(path.join(watchDir, 'test/GeaWatchCounterUITests.swift'), 'sourcecode.swift')
const hasUiTests = existing(uiTestSource)

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
const ref = (file) => `${id(`file:${rel(file)}`)} /* ${path.basename(file)} */`
const buildRef = (file, phase) => `${id(`build:${rel(file)}`)} /* ${path.basename(file)} in ${phase} */`
const fwRef = (fw) => `${id(`file:${fw}`)} /* ${fw} */`
const fwBuildRef = (fw) => `${id(`build:${fw}`)} /* ${fw} in Frameworks */`

function addFile(entry, phase) {
  const settings = entry.kind === 'sourcecode.cpp.objcpp' ? ' settings = {COMPILER_FLAGS = "-fobjc-exceptions"; };' : ''
  fileRefs.push(`${ref(entry.file)} = {isa = PBXFileReference; lastKnownFileType = ${entry.kind}; path = ${q(entry.file)}; sourceTree = "<absolute>"; };`)
  buildFiles.push(`${buildRef(entry.file, phase)} = {isa = PBXBuildFile; fileRef = ${ref(entry.file)};${settings} };`)
}

function addFramework(fw) {
  fileRefs.push(`${fwRef(fw)} = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = ${fw}; path = System/Library/Frameworks/${fw}; sourceTree = SDKROOT; };`)
  buildFiles.push(`${fwBuildRef(fw)} = {isa = PBXBuildFile; fileRef = ${fwRef(fw)}; };`)
}

for (const s of sources) addFile(s, 'Sources')
for (const r of resources) addFile(r, 'Resources')
for (const fw of frameworks) addFramework(fw)
if (hasUiTests) {
  addFile(uiTestSource, 'Sources')
  addFramework('XCTest.framework')
}

const includePaths = [
  path.join(watchDir, 'main'),
  iosMainDir,
  generatedDir,
  path.join(appRoot, 'watchos'),
  ...(process.env.GEA_FW_INCLUDE_DIRS || '').split('\n').filter(Boolean),
]

// Settings both targets share: a watch-only watchOS 10 bundle.
const watchSettings = `
				SDKROOT = watchos;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;`

function buildSettings(configuration) {
  const preprocessorDefinitions = [
    'GEA_EMBEDDED_GIF_C_API=1',
    // No text field to host a native input in, and no room for a keyboard.
    'GEA_EMBEDDED_ENABLE_NATIVE_TEXT_INPUT=0',
    'GEA_EMBEDDED_ENABLE_VIRTUAL_KEYBOARD=0',
    'GEA_CPP_USE_TO_CHARS_DOUBLE=0',
    'GEA_CPP_USE_FROM_CHARS_DOUBLE=0',
    // Full colour like iOS: pixel::native_t is RGBA8888 (1 == GEA_PIXEL_RGBA8888).
    'GEA_EMBEDDED_PIXEL_FORMAT=1',
    // The ratio watchos_host.mm lays the app out at; the font atlas was baked
    // at the same one.
    `GEA_EMBEDDED_CSS_LAYOUT_DEVICE_PIXEL_RATIO=${cssDevicePixelRatio}`,
    ...(hasGeneratedFonts ? ['GEA_EMBEDDED_HAS_GENERATED_FONTS=1'] : []),
  ]
  return `{
				ALWAYS_SEARCH_USER_PATHS = NO;${hasAppIcon ? `
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;` : ''}
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
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				ONLY_ACTIVE_ARCH = ${configuration === 'Debug' ? 'YES' : 'NO'};
				PRODUCT_BUNDLE_IDENTIFIER = ${q(bundleId)};
				PRODUCT_NAME = ${q(appName)};
				SKIP_INSTALL = NO;
				SWIFT_OBJC_BRIDGING_HEADER = ${q(path.join(watchDir, 'main/watchos_bridge.h'))};
				SWIFT_OPTIMIZATION_LEVEL = ${configuration === 'Debug' ? '"-Onone"' : '"-O"'};${watchSettings}
			}`
}

function uiTestBuildSettings(configuration) {
  return `{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
				ONLY_ACTIVE_ARCH = ${configuration === 'Debug' ? 'YES' : 'NO'};
				PRODUCT_BUNDLE_IDENTIFIER = ${q(`${bundleId}.ui-tests`)};
				PRODUCT_NAME = GeaWatchUITests;
				TEST_TARGET_NAME = GeaWatch;${watchSettings}
			}`
}

const appProduct = `${productId} /* ${appName}.app */`
const uiTestProduct = `${uiTestProductId} /* GeaWatchUITests.xctest */`
const mainGroupChildren = [
  ...sources.map((s) => ref(s.file)),
  ...resources.map((r) => ref(r.file)),
  ...frameworks.map(fwRef),
  ...(hasUiTests ? [ref(uiTestSource.file), fwRef('XCTest.framework')] : []),
  `${productGroupId} /* Products */`,
]
const nativeTargets = [
  `${targetId} = {isa = PBXNativeTarget; buildConfigurationList = ${configListTargetId}; buildPhases = (${sourcesPhaseId}, ${frameworksPhaseId}, ${resourcesPhaseId}); buildRules = (); dependencies = (); name = GeaWatch; productName = ${q(appName)}; productReference = ${appProduct}; productType = "com.apple.product-type.application"; };`,
  ...(hasUiTests ? [`${uiTestTargetId} = {isa = PBXNativeTarget; buildConfigurationList = ${uiTestConfigListId}; buildPhases = (${uiTestSourcesPhaseId}, ${uiTestFrameworksPhaseId}); buildRules = (); dependencies = (${uiTestDependencyId}); name = GeaWatchUITests; productName = GeaWatchUITests; productReference = ${uiTestProduct}; productType = "com.apple.product-type.bundle.ui-testing"; };`] : []),
]
const targetAttributes = `${targetId} = {CreatedOnToolsVersion = 16.0;};${hasUiTests ? ` ${uiTestTargetId} = {CreatedOnToolsVersion = 16.0; TestTargetID = ${targetId};};` : ''}`

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		${buildFiles.join('\n\t\t')}
/* End PBXBuildFile section */
${hasUiTests ? `
/* Begin PBXContainerItemProxy section */
		${uiTestProxyId} = {isa = PBXContainerItemProxy; containerPortal = ${projectId} /* Project object */; proxyType = 1; remoteGlobalIDString = ${targetId}; remoteInfo = GeaWatch; };
/* End PBXContainerItemProxy section */
` : ''}
/* Begin PBXFileReference section */
		${fileRefs.join('\n\t\t')}
		${appProduct} = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ${q(`${appName}.app`)}; sourceTree = BUILT_PRODUCTS_DIR; };${hasUiTests ? `
		${uiTestProduct} = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = GeaWatchUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };` : ''}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${frameworksPhaseId} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (${frameworks.map(fwBuildRef).join(', ')}); runOnlyForDeploymentPostprocessing = 0; };${hasUiTests ? `
		${uiTestFrameworksPhaseId} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (${fwBuildRef('XCTest.framework')}); runOnlyForDeploymentPostprocessing = 0; };` : ''}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${mainGroupId} = {isa = PBXGroup; children = (${mainGroupChildren.join(', ')}); sourceTree = "<group>"; };
		${productGroupId} = {isa = PBXGroup; children = (${[appProduct, ...(hasUiTests ? [uiTestProduct] : [])].join(', ')}); name = Products; sourceTree = "<group>"; };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${nativeTargets.join('\n\t\t')}
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${projectId} = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600; TargetAttributes = {${targetAttributes}};}; buildConfigurationList = ${configListProjectId}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = ${mainGroupId}; productRefGroup = ${productGroupId}; projectDirPath = ""; projectRoot = ""; targets = (${[targetId, ...(hasUiTests ? [uiTestTargetId] : [])].join(', ')}); };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${resourcesPhaseId} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${resources.map((r) => buildRef(r.file, 'Resources')).join(', ')}); runOnlyForDeploymentPostprocessing = 0; };
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${sourcesPhaseId} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${sources.map((s) => buildRef(s.file, 'Sources')).join(', ')}); runOnlyForDeploymentPostprocessing = 0; };${hasUiTests ? `
		${uiTestSourcesPhaseId} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${buildRef(uiTestSource.file, 'Sources')}); runOnlyForDeploymentPostprocessing = 0; };` : ''}
/* End PBXSourcesBuildPhase section */
${hasUiTests ? `
/* Begin PBXTargetDependency section */
		${uiTestDependencyId} = {isa = PBXTargetDependency; target = ${targetId} /* GeaWatch */; targetProxy = ${uiTestProxyId}; };
/* End PBXTargetDependency section */
` : ''}
/* Begin XCBuildConfiguration section */
		${debugProjectId} = {isa = XCBuildConfiguration; buildSettings = {}; name = Debug; };
		${releaseProjectId} = {isa = XCBuildConfiguration; buildSettings = {}; name = Release; };
		${debugTargetId} = {isa = XCBuildConfiguration; buildSettings = ${buildSettings('Debug')}; name = Debug; };
		${releaseTargetId} = {isa = XCBuildConfiguration; buildSettings = ${buildSettings('Release')}; name = Release; };${hasUiTests ? `
		${uiTestDebugId} = {isa = XCBuildConfiguration; buildSettings = ${uiTestBuildSettings('Debug')}; name = Debug; };
		${uiTestReleaseId} = {isa = XCBuildConfiguration; buildSettings = ${uiTestBuildSettings('Release')}; name = Release; };` : ''}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${configListProjectId} = {isa = XCConfigurationList; buildConfigurations = (${debugProjectId}, ${releaseProjectId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
		${configListTargetId} = {isa = XCConfigurationList; buildConfigurations = (${debugTargetId}, ${releaseTargetId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };${hasUiTests ? `
		${uiTestConfigListId} = {isa = XCConfigurationList; buildConfigurations = (${uiTestDebugId}, ${uiTestReleaseId}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };` : ''}
/* End XCConfigurationList section */
	};
	rootObject = ${projectId};
}
`

const buildable = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${targetId}" BuildableName="${appName}.app" BlueprintName="GeaWatch" ReferencedContainer="container:GeaWatch.xcodeproj"/>`
const uiTestBuildable = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${uiTestTargetId}" BuildableName="GeaWatchUITests.xctest" BlueprintName="GeaWatchUITests" ReferencedContainer="container:GeaWatch.xcodeproj"/>`
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES" buildArchitectures="Automatic">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        ${buildable}
      </BuildActionEntry>${hasUiTests ? `
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">
        ${uiTestBuildable}
      </BuildActionEntry>` : ''}
    </BuildActionEntries>
  </BuildAction>${hasUiTests ? `
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES" shouldAutocreateTestPlan="YES">
    <Testables>
      <TestableReference skipped="NO">
        ${uiTestBuildable}
      </TestableReference>
    </Testables>
    <MacroExpansion>
      ${buildable}
    </MacroExpansion>
  </TestAction>` : ''}
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      ${buildable}
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      ${buildable}
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
fs.writeFileSync(path.join(projectPath, 'xcshareddata/xcschemes/GeaWatch.xcscheme'), scheme)
console.log(`Generated ${projectPath}`)

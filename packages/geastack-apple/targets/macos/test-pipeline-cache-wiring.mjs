import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
const script = readFileSync(scriptPath, 'utf8')

assert.match(script, /GEA_MACOS_PIPELINE_CACHE:-1/, 'pipeline caching should be enabled by default')
assert.match(
  script,
  /-f "\$ninja_inputs_file"[^]*cmp -s "\$ninja_inputs_tmp" "\$ninja_inputs_file"[^]*ninja -C "\$BUILD_DIR"[^]*return/,
  'an unchanged Ninja input manifest should bypass graph emission',
)
assert.doesNotMatch(script, /\$\(ninja_(?:escape_path|shell_quote)/, 'Ninja graph emission should not fork per path')
assert.match(script, /GEATSC_GENERATED_SOURCE_KEYS/, 'generated-source membership should use a Bash-3-compatible key set')
assert.match(script, /grep -lE '__bridge\|GeaAppleObjCTarget/, 'Objective-C++ routing should scan generated sources in one grep')

for (const [mode, flag] of [
  ['none', '-g0'],
  ['line-tables', '-gline-tables-only'],
  ['full', '-g'],
]) {
  assert.match(script, new RegExp(`${mode.replace('-', '\\-')}\\) GEA_MACOS_DEBUG_INFO="${flag}"`))
}
assert.match(script, /GEA_MACOS_DEBUG_INFO:-none/, 'full DWARF should not be the default')
assert.match(script, /memory >= 68719476736[^]*jobs=8/, 'large-memory hosts should use eight workers')
assert.match(script, /memory >= 103079215104[^]*jobs=12/, '96-GiB hosts should use twelve workers')
assert.match(script, /jobs=4[^]*memory >= 68719476736/, 'smaller hosts should remain capped at four workers')
assert.match(script, /jobs > logical[^]*jobs="\$logical"/, 'automatic jobs should not exceed logical CPUs')

assert.match(script, /GEA_MACOS_TIMINGS:-0/, 'phase timings should be opt-in')
assert.match(
  script,
  /CLANG_CMD=\(\$\{CCACHE_PREFIX\[@\]\+"\$\{CCACHE_PREFIX\[@\]\}"\} clang\)/,
  'disabling ccache must keep the optional prefix safe under macOS Bash 3.2 set -u',
)
assert.match(script, /timing_mark generation[^]*timing_mark source-graph[^]*timing_mark pch[^]*timing_mark compile[^]*timing_mark link[^]*timing_mark resources[^]*timing_mark codesign/)
assert.match(script, /ICON_INPUT_SIGNATURE_FILE[^]*ICON_NEEDED/, 'icon conversion should have an input signature cache')
assert.match(script, /sync-resources\.mjs/, 'owned resources should use the content-stable synchronizer')
assert.match(script, /CODESIGN_STAMP[^]*CODESIGN_NEEDED[^]*codesign --force/, 'codesign should run only after bundle changes')
assert.match(script, /if ! codesign --force[^]*exit 1/, 'codesign failures must fail the build')
assert.match(script, /check-module-graph-freshness\.mjs/, 'resolved module-graph inputs should invalidate generation')
assert.match(script, /compilerFingerprint="\$\(node "\$ROOT_DIR\/targets\/macos\/compiler-input-fingerprint\.mjs" "\$GEA_COMPILER"\)"/,
  'compiler generation fingerprint must include its shipped modules and source runtime')
const generationInputs = script.slice(script.indexOf('find_generation_input_newer_than() {'), script.indexOf('tree_fingerprint() {'))
assert.doesNotMatch(generationInputs, /"\$GEA_COMPILER\/dist"/, 'mtime scanning must not reintroduce native-test artifact invalidation')
assert.match(script, /\.gea-current-apple-native/, 'Apple-native bridge output should have current-generation ownership')
assert.match(script, /finalize-apple-native-output\.mjs/, 'Apple-native ownership should come from finalized compiler output')
assert.match(script, /apple_native_cached_output_is_current/, 'cached Apple-native output should be revalidated before a no-op build')
assert.match(script, /appRuntime[^]*--apple-native/, 'declared Apple-native apps should not rely on source-text import detection')
assert.match(
  script,
  /"\$appRuntime" == "apple-native" && "\$cachedAppleState" != "1"[^]*apple-native-runtime-state/,
  'a declared Apple-native app must not accept cached non-Apple state as a no-op',
)
assert.match(script, /rm -f "\$generationSentinel" "\$appleStateFile"/, 'failed generation should invalidate freshness state')
assert.doesNotMatch(script, /rm -f "\$outDir\/gea-apple-metadata\.json"/, 'generation must not create a metadata deletion window')
assert.match(script, /rm -f "\$sigFile" "\$failFile" "\$pchTmp"/, 'PCH completion and stale failure must be invalidated before writing')
assert.match(script, /LINK_OUTPUT_TMP[^]*rm -f "\$LINK_SIGNATURE_FILE"[^]*mv "\$LINK_OUTPUT_TMP" "\$LINK_OUTPUT"/, 'link output should publish atomically with signature invalidation')

assert.match(script, /APP_META_CACHE_IDS/, 'app metadata should be cached by id under Bash 3.2')
assert.equal(
  script.match(/apps inspect "\$id" --format shell/g)?.length ?? 0,
  1,
  'all per-app metadata fields should share one cached inspect call site',
)
const generationFunctionStart = script.indexOf('generate_app() {')
const generationFunctionEnd = script.indexOf('\n}\n\nprune_geatsc_modules()', generationFunctionStart)
const generationFunction = script.slice(generationFunctionStart, generationFunctionEnd)
assert.match(generationFunction, /resolve_app_meta "\$id"/, 'generation should populate the parent-shell metadata cache once')
assert.doesNotMatch(
  generationFunction,
  /resolve_app_(?:dir|entry|runtime)/,
  'generation must not perform separate inspect-backed field lookups',
)
const freshnessStart = generationFunction.indexOf('if [[ -f "$sourceList" && -f "$generationSentinel" ]]')
const generationDecision = generationFunction.indexOf('if [[ ! -f "$sourceList"', freshnessStart)
const freshnessBlock = generationFunction.slice(freshnessStart, generationDecision)
assert.doesNotMatch(
  freshnessBlock,
  /node .*finalize-apple-native-output/,
  'resident no-op validation must not spawn one Node finalizer per app',
)
assert.match(freshnessBlock, /apple_native_cached_output_is_current/, 'no-op validation should use the cheap read-only check')

const generationRun = script.indexOf('if ! macos_run_tracked_child node "$GEA_CORE/scripts/build-gea-vite-geatsc.mjs"')
const graphOnlySuccess = script.indexOf('Generated module graph only for', generationRun)
const appleFinalization = script.indexOf('local appleFinalizeArgs=', generationRun)
assert.ok(generationRun >= 0, 'could not find the C++ generator invocation')
assert.match(
  script.slice(generationRun, graphOnlySuccess),
  /--geatsc-bin "\$\{GEA_GEATSC_BIN:-\$GEA_COMPILER\/dist\/cli\.js\}"/,
  'C++ generation must use the resolved compiler by default',
)
assert.match(script, /GEA_GEATSC_FINGERPRINT=\$\(tree_fingerprint/, 'an explicit compiler override must also participate in invalidation')
assert.ok(graphOnlySuccess > generationRun, 'graph-only success handling must follow successful graph generation')
assert.ok(
  graphOnlySuccess < appleFinalization,
  'graph-only generation must exit before Apple-native finalization or freshness-state publication',
)
assert.match(
  script.slice(graphOnlySuccess, appleFinalization),
  /exit 0/,
  'successful graph-only generation must terminate the build before native-output finalization',
)
const generationFailure = script.indexOf('Module graph generation failed for', generationRun)
const nativeStateInvalidation = script.indexOf('rm -f "$generationSentinel" "$appleStateFile"', generationRun)
assert.ok(
  generationFailure > generationRun && generationFailure < nativeStateInvalidation,
  'failed graph-only generation must return before invalidating native generation state',
)
assert.match(
  script.slice(generationFailure, nativeStateInvalidation),
  /return 1/,
  'failed graph-only generation must preserve native freshness state by returning early',
)

console.log('macOS pipeline cache wiring tests passed')

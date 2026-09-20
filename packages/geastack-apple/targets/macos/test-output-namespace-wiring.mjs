import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
const script = readFileSync(scriptPath, 'utf8')
const namespaceFunction = script.match(/configure_macos_output_namespace\(\) \{[\s\S]*?\n\}/)?.[0] ?? ''

assert.ok(namespaceFunction, 'could not extract configure_macos_output_namespace')
assert.match(script, /MACOS_OUTPUT_TAG="\$\{GEA_MACOS_OUTPUT_TAG:-\}"/, 'the environment should provide an automation fallback')
assert.match(script, /--output-tag\)/, 'the build script should accept an explicit output tag')
// Output is rooted at MACOS_OUTPUT_ROOT rather than a fixed path inside this
// package, so a build writes beside the apps it builds and an installed copy
// under node_modules is never written into. What the namespace has to
// guarantee is unchanged: both trees are keyed by the resolved subpath.
assert.match(
  script,
  /MACOS_OUTPUT_ROOT="\$\{GEA_MACOS_OUTPUT_DIR:-\$BUILD_INVOCATION_CWD\/dist\/macos\}"/,
  'the output root must be overridable and otherwise land beside the apps',
)
assert.match(
  script,
  /DIST_DIR="\$MACOS_OUTPUT_ROOT\/\$MACOS_OUTPUT_SUBPATH"/,
  'dist output must use the resolved namespace',
)
assert.match(
  script,
  /GENERATED_DIR="\$MACOS_OUTPUT_ROOT\/\.generated\/\$MACOS_OUTPUT_SUBPATH"/,
  'generated output must use the resolved namespace',
)
assert.match(script, /BUILD_LOCK_DIR="\$DIST_DIR\/\.build\.lock"/, 'the correctness lock must be namespace-local')

function resolveNamespace(appId, outputTag) {
  const fixture = `
set -euo pipefail
MACOS_OUTPUT_SUBPATH=""
MACOS_BUILD_LABEL=""
${namespaceFunction}
configure_macos_output_namespace "$1" "$2"
printf '%s\n%s\n' "$MACOS_OUTPUT_SUBPATH" "$MACOS_BUILD_LABEL"
`
  return spawnSync('/bin/bash', ['-c', fixture, '_', appId, outputTag], { encoding: 'utf8', timeout: 2000 })
}

const legacy = resolveNamespace('demo-app', '')
assert.equal(legacy.status, 0, legacy.stderr)
assert.deepEqual(legacy.stdout.trim().split('\n'), ['demo-app', 'demo-app'], 'an unset tag must preserve the legacy cache path')

const outline = resolveNamespace('demo-app', 'outline')
assert.equal(outline.status, 0, outline.stderr)
assert.deepEqual(outline.stdout.trim().split('\n'), ['.namespaces/outline/demo-app', 'demo-app@outline'])

const baseline = resolveNamespace('demo-app', 'baseline')
assert.equal(baseline.status, 0, baseline.stderr)
assert.deepEqual(baseline.stdout.trim().split('\n'), ['.namespaces/baseline/demo-app', 'demo-app@baseline'])
assert.notEqual(outline.stdout, baseline.stdout, 'different tags must receive different generated/dist trees and locks')

for (const invalid of ['../escape', 'nested/tag', '.hidden', '-dash', '_underscore', 'contains space', 'x'.repeat(65)]) {
  const result = resolveNamespace('demo-app', invalid)
  assert.notEqual(result.status, 0, `invalid tag should be rejected: ${invalid}`)
  assert.match(result.stderr, /Invalid macOS output tag/)
}

console.log('macOS output namespace wiring tests passed')

#!/usr/bin/env node

import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { compilerInputFingerprint } from './compiler-input-fingerprint.mjs'

const here = path.dirname(new URL(import.meta.url).pathname)
const syncScript = path.join(here, 'sync-resources.mjs')
const pruneScript = path.join(here, 'prune-generated-modules.mjs')
const graphFreshnessScript = path.join(here, 'check-module-graph-freshness.mjs')
const appleNativeFinalizer = path.join(here, 'finalize-apple-native-output.mjs')
const buildScript = fs.readFileSync(path.join(here, 'build-macos.sh'), 'utf8')
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'gea-macos-pipeline-'))

function extractShellFunction(name) {
  const start = buildScript.indexOf(`${name}() {`)
  const end = buildScript.indexOf('\n}', start)
  assert.ok(start >= 0 && end > start, `could not extract ${name} from build-macos.sh`)
  return buildScript.slice(start, end + 2)
}

const appMetaResolver = extractShellFunction('resolve_app_meta')
const cachedAppleOutputCheck = extractShellFunction('apple_native_cached_output_is_current')

function run(script, args) {
  const result = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  return result.stdout
}

function runCachedAppleOutputCheck(outDir, expectedState) {
  return spawnSync(
    '/bin/bash',
    ['-c', `set -euo pipefail\n${cachedAppleOutputCheck}\napple_native_cached_output_is_current "$1" "$2"`, '_', outDir, expectedState],
    { encoding: 'utf8' },
  )
}

try {
  const compilerRoot = path.join(temporaryRoot, 'compiler')
  const compilerDist = path.join(compilerRoot, 'dist')
  const compilerRuntime = path.join(compilerRoot, 'src/targets/cpp/runtime')
  fs.mkdirSync(compilerDist, { recursive: true })
  fs.mkdirSync(compilerRuntime, { recursive: true })
  fs.writeFileSync(path.join(compilerRoot, 'package.json'), '{"version":"1"}')
  fs.writeFileSync(path.join(compilerDist, 'compiler.js'), 'export const version = 1')
  fs.writeFileSync(path.join(compilerDist, 'compiler.d.ts'), 'export declare const version: number')
  fs.writeFileSync(path.join(compilerRuntime, 'gea_runtime.h'), 'runtime-v1')
  const compilerBefore = compilerInputFingerprint(compilerRoot)
  for (const name of ['test.cpp', 'test.o', 'test', 'runtime.pch', 'runtime.pch.json', 'build.log', 'package.tgz']) {
    fs.writeFileSync(path.join(compilerDist, name), 'native test artifact')
  }
  assert.equal(compilerInputFingerprint(compilerRoot), compilerBefore, 'native outputs must not invalidate generation')
  fs.writeFileSync(path.join(compilerRuntime, 'gea_runtime.h'), 'runtime-v2')
  const runtimeChanged = compilerInputFingerprint(compilerRoot)
  assert.notEqual(runtimeChanged, compilerBefore, 'source runtime headers must invalidate generated runtime copies')
  fs.writeFileSync(path.join(compilerDist, 'compiler.js'), 'export const version = 2')
  const implementationChanged = compilerInputFingerprint(compilerRoot)
  assert.notEqual(implementationChanged, runtimeChanged, 'compiler implementation changes must invalidate generation')
  fs.writeFileSync(path.join(compilerDist, 'compiler.d.ts'), 'export declare const version: string')
  assert.notEqual(compilerInputFingerprint(compilerRoot), implementationChanged, 'compiler declarations are implementation inputs')

  const resolverFixture = `
set -euo pipefail
exec 3>&2
GEA_CLI=fixture
APP_META_CACHE_IDS=()
APP_META_CACHE_VALUES=()
RESOLVED_APP_META=""
node() {
  printf 'inspect-called\\n' >&3
  printf '/apps/fixture\\tindex.tsx\\tapple-native\\tFixture App\\n'
}
${appMetaResolver}
resolve_app_meta fixture
test "$RESOLVED_APP_META" = $'/apps/fixture\\tindex.tsx\\tapple-native\\tFixture App'
resolve_app_meta fixture
test "$RESOLVED_APP_META" = $'/apps/fixture\\tindex.tsx\\tapple-native\\tFixture App'
test "\${#APP_META_CACHE_IDS[@]}" -eq 1
`
  const resolverResult = spawnSync('/bin/bash', ['-c', resolverFixture], { encoding: 'utf8' })
  assert.equal(resolverResult.status, 0, resolverResult.stderr)
  assert.equal(
    resolverResult.stderr.match(/inspect-called/g)?.length ?? 0,
    1,
    'repeated metadata resolution should inspect an app only once',
  )

  const appDir = path.join(temporaryRoot, 'app')
  const resourcesDir = path.join(temporaryRoot, 'Resources')
  const resourceManifest = path.join(temporaryRoot, 'build', 'resources.json')
  fs.mkdirSync(path.join(appDir, 'fonts'), { recursive: true })
  fs.writeFileSync(path.join(appDir, 'fonts', 'fixture.woff'), 'font-v1')
  fs.writeFileSync(path.join(appDir, 'style.css'), '@font-face { src: url("./fonts/fixture.woff"); }\n')
  fs.writeFileSync(path.join(appDir, 'macos.json'), '{"width":640}\n')
  fs.mkdirSync(path.join(resourcesDir, 'Fonts'), { recursive: true })
  fs.writeFileSync(path.join(resourcesDir, 'Fonts', 'legacy.woff'), 'stale')
  fs.writeFileSync(path.join(resourcesDir, 'Fonts', 'interrupted.woff.tmp.123'), 'partial')
  fs.writeFileSync(path.join(resourcesDir, 'window.json.tmp.123'), 'partial')
  const containmentGuard = path.join(temporaryRoot, 'must-not-delete')
  fs.writeFileSync(containmentGuard, 'guard')
  fs.mkdirSync(path.dirname(resourceManifest), { recursive: true })
  fs.writeFileSync(resourceManifest, JSON.stringify({ fonts: ['../../must-not-delete', 'legacy.woff'] }))

  const syncArgs = [
    '--resources-dir', resourcesDir,
    '--manifest', resourceManifest,
    '--config-dir', appDir,
    '--app-dir', appDir,
  ]
  assert.match(run(syncScript, syncArgs), /changed=1/)
  assert.equal(fs.readFileSync(path.join(resourcesDir, 'Fonts', 'fixture.woff'), 'utf8'), 'font-v1')
  assert.equal(fs.existsSync(path.join(resourcesDir, 'Fonts', 'legacy.woff')), false)
  assert.equal(fs.existsSync(path.join(resourcesDir, 'Fonts', 'interrupted.woff.tmp.123')), false)
  assert.equal(fs.existsSync(path.join(resourcesDir, 'window.json.tmp.123')), false)
  assert.equal(fs.readFileSync(containmentGuard, 'utf8'), 'guard', 'a corrupt manifest must not escape Fonts/')
  assert.match(run(syncScript, syncArgs), /changed=0/)

  fs.writeFileSync(path.join(appDir, 'fonts', 'fixture.woff'), 'font-v2')
  assert.match(run(syncScript, syncArgs), /changed=1/)
  assert.equal(fs.readFileSync(path.join(resourcesDir, 'Fonts', 'fixture.woff'), 'utf8'), 'font-v2')

  fs.rmSync(path.join(appDir, 'style.css'))
  fs.rmSync(path.join(appDir, 'macos.json'))
  assert.match(run(syncScript, syncArgs), /changed=1/)
  assert.equal(fs.existsSync(path.join(resourcesDir, 'Fonts', 'fixture.woff')), false)
  assert.equal(fs.existsSync(path.join(resourcesDir, 'window.json')), false)

  const generatedDir = path.join(temporaryRoot, 'generated')
  const modulesDir = path.join(generatedDir, 'modules')
  fs.mkdirSync(modulesDir, { recursive: true })
  const writeFamily = (stem, header = '') => {
    fs.writeFileSync(path.join(modulesDir, `${stem}.cpp`), `#include "./${stem}.hpp"\n`)
    fs.writeFileSync(path.join(modulesDir, `${stem}.hpp`), header)
    fs.writeFileSync(path.join(modulesDir, `${stem}.types.hpp`), '')
  }
  writeFamily('0000_active', '#include "./0002_header_only.hpp"\n')
  writeFamily('0001_stale')
  writeFamily('0002_header_only')
  writeFamily('0003_batched')
  writeFamily('0004_batched')
  const activeBatch = path.join(modulesDir, '__gea_data_batch_0000.cpp')
  const staleBatch = path.join(modulesDir, '__gea_data_batch_0001.cpp')
  fs.writeFileSync(activeBatch, '#include "./0003_batched.cpp"\n#include "./0004_batched.cpp"\n')
  fs.writeFileSync(staleBatch, '// stale generated batch\n')
  fs.writeFileSync(path.join(modulesDir, 'gea_ir.hpp'), '// shared support\n')
  fs.writeFileSync(
    path.join(generatedDir, 'geatsc-sources.txt'),
    `${path.join(modulesDir, '0000_active.cpp')}\n${activeBatch}\n`
  )

  const dryRun = JSON.parse(run(pruneScript, ['--out-dir', generatedDir, '--dry-run']))
  assert.equal(dryRun.removedFiles, 4)
  assert.equal(fs.existsSync(path.join(modulesDir, '0001_stale.cpp')), true, 'dry run must not mutate')

  const pruned = JSON.parse(run(pruneScript, ['--out-dir', generatedDir]))
  assert.equal(pruned.removedFiles, 4)
  assert.equal(fs.existsSync(path.join(modulesDir, '0001_stale.cpp')), false)
  assert.equal(fs.existsSync(path.join(modulesDir, '0002_header_only.cpp')), true, 'referenced header-only family stays intact')
  assert.equal(fs.existsSync(path.join(modulesDir, '0003_batched.cpp')), true, 'batch-included source family stays intact')
  assert.equal(fs.existsSync(path.join(modulesDir, '0004_batched.hpp')), true, 'batch-included header family stays intact')
  assert.equal(fs.existsSync(activeBatch), true, 'listed generated batch stays intact')
  assert.equal(fs.existsSync(staleBatch), false, 'unlisted generated batch is pruned')
  assert.equal(fs.existsSync(path.join(modulesDir, 'gea_ir.hpp')), true, 'non-family shared support stays intact')
  assert.equal(fs.existsSync(path.join(generatedDir, '.gea-owned-modules.json')), true)

  const graphDir = path.join(temporaryRoot, 'module-graph')
  const graphSourcesDir = path.join(graphDir, 'sources')
  const graphInput = path.join(temporaryRoot, 'external-library.js')
  const graphSnapshot = path.join(graphSourcesDir, 'external.original.js')
  const graphReference = path.join(temporaryRoot, 'generation.stamp')
  const graphPath = path.join(graphDir, 'gea-module-graph.json')
  fs.mkdirSync(graphSourcesDir, { recursive: true })
  fs.writeFileSync(graphInput, 'source-v1')
  fs.writeFileSync(graphSnapshot, 'source-v1')
  fs.writeFileSync(graphReference, '')
  fs.writeFileSync(graphPath, JSON.stringify({
    modules: [{ file: graphInput, originalSource: 'sources/external.original.js' }],
  }))
  const oldTime = new Date(Date.now() - 20_000)
  const stampTime = new Date(Date.now() - 10_000)
  fs.utimesSync(graphInput, oldTime, oldTime)
  fs.utimesSync(graphReference, stampTime, stampTime)
  const freshnessArgs = ['--graph', graphPath, '--reference', graphReference]
  assert.equal(run(graphFreshnessScript, freshnessArgs), '', 'unchanged resolved inputs should stay fresh')

  fs.writeFileSync(graphInput, 'source-v2')
  fs.utimesSync(graphInput, oldTime, oldTime)
  assert.match(run(graphFreshnessScript, freshnessArgs), /^content:/, 'content changes must survive backdated mtimes')
  fs.writeFileSync(graphInput, 'source-v1')
  fs.utimesSync(graphInput, new Date(), new Date())
  assert.match(run(graphFreshnessScript, freshnessArgs), /^newer:/)
  fs.rmSync(graphInput)
  assert.match(run(graphFreshnessScript, freshnessArgs), /^missing:/)

  const assetInput = path.join(temporaryRoot, 'sound.mp3')
  fs.writeFileSync(assetInput, 'binary-audio')
  fs.utimesSync(assetInput, oldTime, oldTime)
  const assetSha256 = crypto.createHash('sha256').update(fs.readFileSync(assetInput)).digest('hex')
  fs.writeFileSync(graphPath, JSON.stringify({
    modules: [{
      file: `${assetInput}.geaassetstub.js`,
      originalSource: 'sources/external.original.js',
      assetSource: assetInput,
      assetSha256,
    }],
  }))
  assert.equal(run(graphFreshnessScript, freshnessArgs), '', 'asset metadata should resolve to its binary input')
  fs.writeFileSync(assetInput, 'binary-AUDIO')
  fs.utimesSync(assetInput, oldTime, oldTime)
  assert.match(
    run(graphFreshnessScript, freshnessArgs),
    /^content:/,
    'asset digest changes must survive backdated mtimes and synthetic JS snapshots',
  )
  fs.writeFileSync(assetInput, 'binary-audio')
  fs.utimesSync(assetInput, new Date(), new Date())
  assert.match(run(graphFreshnessScript, freshnessArgs), /^newer:/)

  // Keep legacy graphs produced by the former app-local asset plugin fresh
  // during rolling upgrades; they have only the virtual suffix, no metadata.
  fs.utimesSync(assetInput, oldTime, oldTime)
  fs.writeFileSync(graphPath, JSON.stringify({
    modules: [{ file: `${assetInput}.geaassetstub.js`, originalSource: null }],
  }))
  assert.equal(run(graphFreshnessScript, freshnessArgs), '', 'legacy virtual asset ids should still resolve to their binary input')

  const appleOutput = path.join(temporaryRoot, 'apple-output')
  const appleBridgeDir = path.join(appleOutput, 'gea', 'apple')
  const appleSupport = path.join(appleOutput, 'generated_support.hpp')
  const appleBridgeHeader = path.join(appleBridgeDir, 'native_bridge.h')
  const appleBridgeSource = path.join(appleBridgeDir, 'native_bridge.mm')
  fs.mkdirSync(appleOutput, { recursive: true })
  const missingSupport = spawnSync(
    process.execPath,
    [appleNativeFinalizer, '--out-dir', appleOutput, '--check-only', '--expected-state', '0'],
    { encoding: 'utf8' },
  )
  assert.notEqual(missingSupport.status, 0, 'missing generated support must invalidate cached non-Apple output')
  assert.match(missingSupport.stderr, /non-empty generated_support\.hpp/)
  assert.notEqual(runCachedAppleOutputCheck(appleOutput, '0').status, 0)

  fs.writeFileSync(appleSupport, '')
  const emptySupport = spawnSync(process.execPath, [appleNativeFinalizer, '--out-dir', appleOutput], { encoding: 'utf8' })
  assert.notEqual(emptySupport.status, 0, 'empty generated support must fail finalization')
  assert.match(emptySupport.stderr, /non-empty generated_support\.hpp/)
  assert.notEqual(runCachedAppleOutputCheck(appleOutput, '0').status, 0)

  fs.mkdirSync(appleBridgeDir, { recursive: true })
  fs.writeFileSync(appleSupport, '#pragma once\n#include "gea/apple/native_bridge.h"\n')
  fs.writeFileSync(appleBridgeHeader, '#pragma once\n')
  fs.writeFileSync(appleBridgeSource, '// bridge\n')
  assert.equal(run(appleNativeFinalizer, ['--out-dir', appleOutput]), '1')
  assert.equal(fs.existsSync(appleBridgeDir), true, 'current bridge output must remain owned without its metadata input')
  assert.equal(run(appleNativeFinalizer, ['--out-dir', appleOutput, '--check-only', '--expected-state', '1']), '1')
  assert.equal(runCachedAppleOutputCheck(appleOutput, '1').status, 0)

  fs.writeFileSync(appleBridgeHeader, '')
  const emptyHeader = spawnSync(
    process.execPath,
    [appleNativeFinalizer, '--out-dir', appleOutput, '--check-only', '--expected-state', '1'],
    { encoding: 'utf8' },
  )
  assert.notEqual(emptyHeader.status, 0, 'an empty native bridge header must invalidate cached Apple output')
  assert.match(emptyHeader.stderr, /native_bridge\.h/)
  assert.notEqual(runCachedAppleOutputCheck(appleOutput, '1').status, 0)
  fs.writeFileSync(appleBridgeHeader, '#pragma once\n')

  fs.writeFileSync(appleBridgeSource, '')
  const emptySource = spawnSync(process.execPath, [appleNativeFinalizer, '--out-dir', appleOutput], { encoding: 'utf8' })
  assert.notEqual(emptySource.status, 0, 'an empty native bridge source must fail finalization')
  assert.match(emptySource.stderr, /native_bridge\.mm/)
  assert.notEqual(runCachedAppleOutputCheck(appleOutput, '1').status, 0)
  fs.writeFileSync(appleBridgeSource, '// bridge\n')

  fs.writeFileSync(path.join(appleOutput, 'gea-apple-metadata.json'), '{}\n')
  fs.writeFileSync(appleSupport, '#pragma once\n')
  assert.notEqual(
    runCachedAppleOutputCheck(appleOutput, '0').status,
    0,
    'cached non-Apple output with stale Apple files must be rejected before cleanup',
  )
  const staleNonApple = spawnSync(
    process.execPath,
    [appleNativeFinalizer, '--out-dir', appleOutput, '--check-only', '--expected-state', '0'],
    { encoding: 'utf8' },
  )
  assert.notEqual(staleNonApple.status, 0, 'the authoritative check-only path must also reject stale Apple files')
  assert.match(staleNonApple.stderr, /retains stale Apple-native files/)
  assert.equal(run(appleNativeFinalizer, ['--out-dir', appleOutput]), '0')
  assert.equal(fs.existsSync(appleBridgeDir), false, 'a successful non-Apple generation must remove stale bridge output')
  assert.equal(fs.existsSync(path.join(appleOutput, 'gea-apple-metadata.json')), false, 'stale metadata must be removed with the bridge')
  assert.equal(runCachedAppleOutputCheck(appleOutput, '0').status, 0)

  fs.mkdirSync(appleBridgeDir, { recursive: true })
  fs.writeFileSync(appleSupport, '#pragma once\n#include "gea/apple/native_bridge.h"\n')
  fs.writeFileSync(appleBridgeHeader, '#pragma once\n')
  const inconsistent = spawnSync(process.execPath, [appleNativeFinalizer, '--out-dir', appleOutput], { encoding: 'utf8' })
  assert.notEqual(inconsistent.status, 0, 'an included but incomplete bridge must fail before native compilation')
  assert.match(inconsistent.stderr, /native_bridge\.mm/)
  assert.notEqual(runCachedAppleOutputCheck(appleOutput, '1').status, 0)

  fs.writeFileSync(path.join(appleOutput, 'gea-apple-metadata.json'), '{}\n')
  fs.writeFileSync(appleSupport, '#pragma once\n')
  const expectedApple = spawnSync(
    process.execPath,
    [appleNativeFinalizer, '--out-dir', appleOutput, '--expected-state', '1'],
    { encoding: 'utf8' }
  )
  assert.notEqual(expectedApple.status, 0, 'declared Apple-native apps must not silently publish non-Apple output')
  assert.equal(fs.existsSync(path.join(appleOutput, 'gea-apple-metadata.json')), true, 'failed validation must preserve forensic state')
  assert.equal(fs.existsSync(appleBridgeDir), true, 'failed validation must not prune bridge output')
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log('macOS pipeline cache helper tests passed')

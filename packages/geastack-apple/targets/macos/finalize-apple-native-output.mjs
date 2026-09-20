#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

function readOption(name) {
  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : undefined
}

function hasFlag(name) {
  return process.argv.includes(name)
}

function isNonEmptyFile(filePath) {
  try {
    const stats = fs.statSync(filePath)
    return stats.isFile() && stats.size > 0
  } catch {
    return false
  }
}

const outDirOption = readOption('--out-dir')
if (!outDirOption) fail('usage: finalize-apple-native-output.mjs --out-dir <generated-dir>')

const outDir = path.resolve(outDirOption)
const checkOnly = hasFlag('--check-only')
const expectedState = readOption('--expected-state')
if (expectedState !== undefined && expectedState !== '0' && expectedState !== '1') {
  fail('--expected-state must be 0 or 1')
}
const supportPath = path.join(outDir, 'generated_support.hpp')
const metadataPath = path.join(outDir, 'gea-apple-metadata.json')
const bridgeDir = path.join(outDir, 'gea', 'apple')
const bridgeHeader = path.join(bridgeDir, 'native_bridge.h')
const bridgeSource = path.join(bridgeDir, 'native_bridge.mm')
const bridgeInclude = '#include "gea/apple/native_bridge.h"'
if (!isNonEmptyFile(supportPath)) {
  fail(`generation did not produce a non-empty generated_support.hpp: ${supportPath}`)
}
const support = fs.readFileSync(supportPath, 'utf8')

let state
if (support.includes(bridgeInclude)) {
  const missing = [bridgeHeader, bridgeSource].filter((file) => !isNonEmptyFile(file))
  if (missing.length > 0) {
    fail(`generated_support.hpp includes the Apple native bridge, but generation did not produce non-empty files: ${missing.join(', ')}`)
  }
  state = '1'
} else {
  state = '0'
}

if (expectedState !== undefined && state !== expectedState) {
  fail(`generated Apple-native state ${state} does not match expected state ${expectedState}`)
}

if (checkOnly) {
  if (state === '0') {
    const stale = [metadataPath, bridgeDir].filter((file) => fs.existsSync(file))
    if (stale.length > 0) fail(`cached non-Apple output retains stale Apple-native files: ${stale.join(', ')}`)
  }
} else if (state === '0') {
  // The compiler does not own stale plugin output. Remove it only after a
  // successful generation whose transformed support no longer references the
  // bridge; failed generations therefore retain their last complete tree.
  fs.rmSync(bridgeDir, { recursive: true, force: true })
  fs.rmSync(metadataPath, { force: true })
}

process.stdout.write(state)

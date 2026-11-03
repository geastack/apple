#!/usr/bin/env node
// Merge the optional `infoPlist` object of an app's macos.json into the
// generated Info.plist, so an app can declare its own keys (for example
// NSCalendarsFullAccessUsageDescription) without a per-app template. Each key
// is written with `plutil -replace`, so values may be any JSON plutil accepts:
// strings, numbers, booleans, arrays and objects.
//
//   node merge-info-plist.mjs <Info.plist> <macos.json>
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const [plist, config] = process.argv.slice(2)
if (!plist || !config) {
  console.error('usage: merge-info-plist.mjs <Info.plist> <macos.json>')
  process.exit(2)
}
const fail = (message) => {
  console.error(`${config}: ${message}`)
  process.exit(1)
}
let parsed
try {
  parsed = JSON.parse(readFileSync(config, 'utf8'))
} catch (error) {
  fail(`cannot read JSON (${error.message})`)
}
const entries = parsed?.infoPlist
if (entries === undefined) process.exit(0)
if (entries === null || typeof entries !== 'object' || Array.isArray(entries)) fail('infoPlist must be an object')
for (const [key, value] of Object.entries(entries)) {
  // plutil reads a dot as a key-path separator.
  if (!key || key.includes('.')) fail(`infoPlist key ${JSON.stringify(key)} must be a non-empty name without dots`)
  if (value === null) fail(`infoPlist.${key} must not be null`)
  execFileSync('plutil', ['-replace', key, '-json', JSON.stringify(value), plist], { stdio: ['ignore', 'ignore', 'inherit'] })
}

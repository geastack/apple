import assert from 'node:assert/strict'
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync, spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

if (process.platform !== 'darwin') process.exit(0)

const merge = fileURLToPath(new URL('./merge-info-plist.mjs', import.meta.url))
const template = fileURLToPath(new URL('./Info.plist.in', import.meta.url))
const script = readFileSync(fileURLToPath(new URL('./build-macos.sh', import.meta.url)), 'utf8').replace(/\r\n/g, '\n')

// The merge runs on the temporary plist before the stable replace, so an
// unchanged macos.json leaves the bundle untouched.
const mergeAt = script.indexOf('merge-info-plist.mjs" "$INFO_PLIST_TMP"')
assert.notEqual(mergeAt, -1, 'build-macos.sh should merge macos.json infoPlist into the generated Info.plist')
assert.ok(mergeAt > script.indexOf('resolve_app_dir() {'), 'the merge needs resolve_app_dir to be defined')
assert.ok(mergeAt < script.indexOf('replace_content_stable "$APP_BUNDLE/Contents/Info.plist"'), 'merge before replacing the bundle plist')
assert.match(script, /-framework EventKit/)

const dir = mkdtempSync(path.join(os.tmpdir(), 'gea-info-plist-'))
try {
  const plist = path.join(dir, 'Info.plist')
  const config = path.join(dir, 'macos.json')
  const read = () => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', plist], { encoding: 'utf8' }))
  const run = (json) => {
    copyFileSync(template, plist)
    writeFileSync(config, JSON.stringify(json))
    return spawnSync(process.execPath, [merge, plist, config], { encoding: 'utf8' })
  }

  assert.equal(run({ window: { width: 800 } }).status, 0)
  assert.equal(read().NSCalendarsFullAccessUsageDescription, undefined)

  const result = run({
    window: { width: 800 },
    infoPlist: {
      NSCalendarsFullAccessUsageDescription: 'Shows your meetings next to your tasks.',
      NSCalendarsUsageDescription: 'Shows your meetings next to your tasks.',
      LSUIElement: true,
      LSApplicationCategoryType: 'public.app-category.productivity'
    }
  })
  assert.equal(result.status, 0, result.stderr)
  const merged = read()
  assert.equal(merged.NSCalendarsFullAccessUsageDescription, 'Shows your meetings next to your tasks.')
  assert.equal(merged.LSUIElement, true)
  assert.equal(merged.NSPrincipalClass, 'NSApplication', 'template keys are kept')
  execFileSync('plutil', ['-lint', plist], { stdio: 'ignore' })

  for (const infoPlist of [[], 'text', { 'a.b': 'x' }, { key: null }]) {
    const rejected = run({ infoPlist })
    assert.equal(rejected.status, 1, JSON.stringify(infoPlist))
    assert.match(rejected.stderr, /infoPlist/)
  }
} finally {
  rmSync(dir, { recursive: true, force: true })
}
console.log('macos.json infoPlist merge passed')

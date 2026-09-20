import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
const script = readFileSync(scriptPath, 'utf8')

assert.match(script, /source "\$ROOT_DIR\/targets\/macos\/heavy-build-lock\.sh"/)
assert.match(script, /source "\$ROOT_DIR\/targets\/macos\/build-child-lifecycle\.sh"/)

const globalAcquire = script.indexOf('gea_acquire_heavy_build_lock "$HEAVY_BUILD_LOCK_PATH" macos "$MACOS_BUILD_LABEL"')
const localAcquire = script.indexOf('\nacquire_build_lock\n', globalAcquire)
assert.notEqual(globalAcquire, -1, 'macOS build should acquire the workspace resource lock')
assert.ok(localAcquire > globalAcquire, 'workspace lock must be acquired before the output-namespace lock')

const cleanup = script.match(/cleanup_build_locks\(\) \{([\s\S]*?)\n\}/)?.[1] ?? ''
assert.ok(cleanup.indexOf('release_build_lock') >= 0, 'cleanup should release the output-namespace lock')
assert.ok(
  cleanup.indexOf('macos_terminate_and_reap_build_children') < cleanup.indexOf('release_build_lock'),
  'cleanup must terminate and reap build children before releasing the output-namespace lock',
)
assert.ok(
  cleanup.indexOf('gea_release_heavy_build_lock') > cleanup.indexOf('release_build_lock'),
  'cleanup should release locks in reverse acquisition order',
)
assert.match(script, /trap cleanup_build_locks EXIT/)
assert.match(script, /trap 'handle_build_interrupt 130' INT/)
assert.match(script, /trap 'handle_build_interrupt 143' TERM/)

const distCreate = script.indexOf('mkdir -p "$DIST_DIR"')
assert.ok(distCreate >= 0 && distCreate < localAcquire, 'a clean app must create its dist parent before acquiring the local lock')

const acquireFunction = script.match(/acquire_build_lock\(\) \{[\s\S]*?\n\}/)?.[0] ?? ''
assert.ok(acquireFunction, 'could not extract acquire_build_lock for fixture test')
const temporaryRoot = mkdtempSync(path.join(os.tmpdir(), 'gea-macos-local-lock-'))
try {
  const absentDist = path.join(temporaryRoot, 'new-app', 'dist')
  const fixture = `
set -euo pipefail
DIST_DIR="$1"
APP_ID=fixture
mkdir -p "$DIST_DIR"
BUILD_LOCK_DIR="$DIST_DIR/.build.lock"
${acquireFunction}
acquire_build_lock
test -f "$BUILD_LOCK_DIR/pid"
`
  const acquired = spawnSync('/bin/bash', ['-c', fixture, '_', absentDist], { encoding: 'utf8', timeout: 2000 })
  assert.equal(acquired.status, 0, acquired.stderr || 'clean build lock fixture failed')

  const missingParentFixture = `
set -euo pipefail
APP_ID=fixture
BUILD_LOCK_DIR="$1/missing-parent/.build.lock"
${acquireFunction}
if acquire_build_lock; then exit 9; fi
`
  const rejected = spawnSync('/bin/bash', ['-c', missingParentFixture, '_', temporaryRoot], { encoding: 'utf8', timeout: 2000 })
  assert.equal(rejected.status, 0, rejected.stderr || 'non-contention mkdir failure fixture failed')
  assert.match(rejected.stderr, /Cannot create macOS build lock/)
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log('macOS heavy-build lock wiring tests passed')

import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { posixBash } from './test/posix-bash.mjs'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
// A Windows checkout has CRLF line ends; the patterns and bash want LF.
const script = readFileSync(scriptPath, 'utf8').replace(/\r\n/g, '\n')

assert.match(script, /source "\$ROOT_DIR\/targets\/macos\/heavy-build-lock\.sh"/)
assert.match(script, /source "\$ROOT_DIR\/targets\/macos\/build-child-lifecycle\.sh"/)
// Every long-running build step is a tracked child, so an interrupt reaps it
// before the locks are released (test-build-child-lifecycle.mjs runs that
// cleanup against real processes where the host has POSIX signals).
assert.match(script, /macos_run_tracked_child node "\$GEA_CORE\/scripts\/build-gea-vite-geatsc\.mjs"/)
assert.match(script, /macos_run_tracked_child ninja -C "\$BUILD_DIR"/)
assert.match(script, /macos_run_tracked_child "\$\{CLANGXX_CMD\[@\]\}"[^]*-x c\+\+-header/)
assert.match(script, /macos_run_tracked_child clang\+\+[^]*"\$LINK_OUTPUT_TMP"/)

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
  const acquired = spawnSync(posixBash, ['-c', fixture, '_', absentDist], { encoding: 'utf8', timeout: 2000 })
  assert.equal(acquired.status, 0, acquired.stderr || 'clean build lock fixture failed')

  const missingParentFixture = `
set -euo pipefail
APP_ID=fixture
BUILD_LOCK_DIR="$1/missing-parent/.build.lock"
${acquireFunction}
if acquire_build_lock; then exit 9; fi
`
  const rejected = spawnSync(posixBash, ['-c', missingParentFixture, '_', temporaryRoot], { encoding: 'utf8', timeout: 2000 })
  assert.equal(rejected.status, 0, rejected.stderr || 'non-contention mkdir failure fixture failed')
  assert.match(rejected.stderr, /Cannot create macOS build lock/)
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log('macOS heavy-build lock wiring tests passed')

import assert from 'node:assert/strict'
import { accessSync, constants, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const directory = path.dirname(fileURLToPath(import.meta.url))
const helperPath = path.join(directory, 'build-child-lifecycle.sh')
const buildScript = readFileSync(path.join(directory, 'build-macos.sh'), 'utf8')

assert.match(buildScript, /macos_run_tracked_child node "\$GEA_CORE\/scripts\/build-gea-vite-geatsc\.mjs"/)
assert.match(buildScript, /macos_run_tracked_child ninja -C "\$BUILD_DIR"/)
assert.match(buildScript, /macos_run_tracked_child "\$\{CLANGXX_CMD\[@\]\}"[^]*-x c\+\+-header/)
assert.match(buildScript, /macos_run_tracked_child clang\+\+[^]*"\$LINK_OUTPUT_TMP"/)

const temporaryRoot = mkdtempSync(path.join(os.tmpdir(), 'gea-macos-child-lifecycle-'))
const workerPath = path.join(temporaryRoot, 'worker.sh')
const fixturePath = path.join(temporaryRoot, 'fixture.sh')

writeFileSync(
  workerPath,
  `#!/usr/bin/env bash
set -euo pipefail
root="$1"
mode="$2"
echo "$$" > "$root/$mode.child.pid"
trap 'printf "%s\\n" child-term >> "$root/'"$mode"'.events"; exit 0' TERM HUP INT
/bin/bash -c 'set -euo pipefail; root="$1"; mode="$2"; echo "$$" > "$root/$mode.grand.pid"; trap "" TERM HUP INT; sleep 3; echo orphan-write > "$root/$mode.orphan"' _ "$root" "$mode" &
grand="$!"
wait "$grand"
`,
  { mode: 0o755 },
)

writeFileSync(
  fixturePath,
  `#!/usr/bin/env bash
set -euo pipefail
helper="$1"
root="$2"
mode="$3"
worker="$4"
source "$helper"
lock="$root/$mode.build.lock"
mkdir "$lock"
cleanup_fixture() {
  local status="$?"
  trap - EXIT HUP INT TERM
  macos_terminate_and_reap_build_children
  printf '%s\\n' lock-release >> "$root/$mode.events"
  rm -rf "$lock"
  return "$status"
}
interrupt_fixture() {
  trap - HUP INT TERM
  exit 143
}
trap cleanup_fixture EXIT
trap interrupt_fixture HUP INT TERM
if [[ "$mode" == tracked ]]; then
  macos_run_tracked_child /bin/bash "$worker" "$root" "$mode"
else
  /bin/bash "$worker" "$root" "$mode" &
  PIDS+=("$!")
  wait "\${PIDS[0]}"
fi
`,
  { mode: 0o755 },
)

const exists = (file) => {
  try {
    accessSync(file, constants.F_OK)
    return true
  } catch {
    return false
  }
}

const waitFor = async (predicate, timeoutMs = 4000) => {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (predicate()) return
    await new Promise((resolve) => setTimeout(resolve, 20))
  }
  throw new Error('timed out waiting for lifecycle fixture')
}

const processIsRunning = (pid) => {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    if (error?.code === 'ESRCH') return false
    throw error
  }
}

const runInterruptFixture = async (mode) => {
  const unrelated = spawn('/bin/bash', ['-c', 'trap "" TERM HUP INT; sleep 10'], { stdio: 'ignore' })
  const fixture = spawn('/bin/bash', [fixturePath, helperPath, temporaryRoot, mode, workerPath], {
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let stderr = ''
  fixture.stderr.setEncoding('utf8')
  fixture.stderr.on('data', (chunk) => {
    stderr += chunk
  })
  const childPidFile = path.join(temporaryRoot, `${mode}.child.pid`)
  const grandPidFile = path.join(temporaryRoot, `${mode}.grand.pid`)
  try {
    await waitFor(() => exists(childPidFile) && exists(grandPidFile))
    const childPid = Number(readFileSync(childPidFile, 'utf8').trim())
    const grandPid = Number(readFileSync(grandPidFile, 'utf8').trim())
    process.kill(fixture.pid, 'SIGTERM')
    const exit = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`fixture ${mode} did not exit`)), 5000)
      fixture.once('close', (code, signal) => {
        clearTimeout(timeout)
        resolve({ code, signal })
      })
    })
    assert.equal(exit.signal, null, `${mode}: fixture should translate TERM into an exit status`)
    assert.equal(exit.code, 143, `${mode}: ${stderr}`)
    assert.equal(exists(path.join(temporaryRoot, `${mode}.build.lock`)), false, `${mode}: lock was not released`)
    const events = readFileSync(path.join(temporaryRoot, `${mode}.events`), 'utf8').trim().split('\n')
    assert.deepEqual(events, ['child-term', 'lock-release'], `${mode}: child must stop before lock release`)
    await new Promise((resolve) => setTimeout(resolve, 100))
    assert.equal(processIsRunning(childPid), false, `${mode}: direct child survived cleanup`)
    assert.equal(processIsRunning(grandPid), false, `${mode}: compiler descendant survived cleanup`)
    assert.equal(exists(path.join(temporaryRoot, `${mode}.orphan`)), false, `${mode}: descendant wrote after interruption`)
    assert.equal(processIsRunning(unrelated.pid), true, `${mode}: unrelated/different-app process was terminated`)
  } finally {
    if (processIsRunning(fixture.pid)) fixture.kill('SIGKILL')
    if (processIsRunning(unrelated.pid)) unrelated.kill('SIGKILL')
  }
}

try {
  await runInterruptFixture('tracked')
  await runInterruptFixture('queued')
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log('macOS build child lifecycle tests passed')

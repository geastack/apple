import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const directory = path.dirname(fileURLToPath(import.meta.url))
const helperPath = path.join(directory, 'build-child-lifecycle.sh')
const helper = readFileSync(helperPath, 'utf8')
assert.doesNotMatch(helper, /\bpkill\b/, 'cleanup must never use a global/name-based process kill')

const temporaryRoot = mkdtempSync(path.join(os.tmpdir(), 'gea-macos-process-tree-'))
const processTable = path.join(temporaryRoot, 'ps.txt')
try {
  writeFileSync(
    processTable,
    [
      '1 0',
      '10 1',
      '11 10',
      '12 11',
      '13 10',
      '20 1',
      '21 20',
      '22 21',
      '30 999',
      '31 30',
      '999 1',
      '',
    ].join('\n'),
  )
  const fixture = `
set -euo pipefail
source "$1"
MACOS_BUILD_PROCESS_TABLE_FILE="$2"
macos_build_process_tree "10 30" | sort -n
`
  const result = spawnSync('/bin/bash', ['-c', fixture, '_', helperPath, processTable], {
    encoding: 'utf8',
    timeout: 2000,
  })
  assert.equal(result.status, 0, result.stderr)
  assert.deepEqual(result.stdout.trim().split('\n'), ['10', '11', '12', '13', '30', '31'])
  for (const unrelated of ['1', '20', '21', '22', '999']) {
    assert.equal(result.stdout.split('\n').includes(unrelated), false, `unrelated pid ${unrelated} leaked into kill tree`)
  }
} finally {
  rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log('macOS build child process-tree tests passed')

import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const helper = fileURLToPath(new URL('./order-compile-edges.mjs', import.meta.url))
const fixture = mkdtempSync(join(tmpdir(), 'gea-compile-order-'))

try {
  const small = join(fixture, 'small.cpp')
  const tieZ = join(fixture, 'z-tie.cpp')
  const tieA = join(fixture, 'a-tie.mm')
  const large = join(fixture, 'large.cpp')
  writeFileSync(small, 'x')
  writeFileSync(tieZ, 'x'.repeat(20))
  writeFileSync(tieA, 'x'.repeat(20))
  writeFileSync(large, 'x'.repeat(100))

  const input = [
    `c\t${small}`,
    `cxx\t${tieZ}`,
    `mm\t${tieA}`,
    `cxx\t${large}`,
  ].join('\n') + '\n'
  const ordered = spawnSync(process.execPath, [helper], { input, encoding: 'utf8' })
  assert.equal(ordered.status, 0, ordered.stderr)
  assert.deepEqual(ordered.stdout.trimEnd().split('\n'), [
    `cxx\t100\t${large}`,
    `mm\t20\t${tieA}`,
    `cxx\t20\t${tieZ}`,
    `c\t1\t${small}`,
  ])

  writeFileSync(small, 'x'.repeat(200))
  const resized = spawnSync(process.execPath, [helper], { input, encoding: 'utf8' })
  assert.equal(resized.status, 0, resized.stderr)
  assert.notEqual(resized.stdout, ordered.stdout, 'source-size changes must invalidate the schedule fingerprint')
  assert.equal(resized.stdout.trimEnd().split('\n')[0], `c\t200\t${small}`)

  const malformed = spawnSync(process.execPath, [helper], {
    input: `swift\t${small}\n`,
    encoding: 'utf8',
  })
  assert.notEqual(malformed.status, 0)
  assert.match(malformed.stderr, /unsupported kind/)

  const ninjaVersion = spawnSync('ninja', ['--version'], { encoding: 'utf8' })
  if (ninjaVersion.status === 0) {
    const records = resized.stdout.trimEnd().split('\n').map(line => {
      const [kind, , source] = line.split('\t')
      return { kind, source, label: basename(source).replace(/\W/g, '_') }
    })
    const graph = [
      'rule observe',
      '  command = true',
      '  description = EDGE $label',
      '',
      ...records.flatMap(({ source, label }) => [
        `build ${label}.o: observe ${basename(source)}`,
        `  label = ${label}`,
      ]),
      '',
      `build all: phony ${records.map(({ label }) => `${label}.o`).join(' ')}`,
      'default all',
      '',
    ].join('\n')
    const graphPath = join(fixture, 'build.ninja')
    writeFileSync(graphPath, graph)

    const dryRun = spawnSync('ninja', ['-f', graphPath, '-j', '1', '-n', 'all'], {
      cwd: fixture,
      encoding: 'utf8',
    })
    assert.equal(dryRun.status, 0, dryRun.stderr)
    const starts = [...dryRun.stdout.matchAll(/EDGE (\S+)/g)].map(match => match[1])
    assert.deepEqual(starts, records.map(({ label }) => label))
  }
} finally {
  rmSync(fixture, { recursive: true, force: true })
}

console.log('macOS compile-edge ordering tests passed')

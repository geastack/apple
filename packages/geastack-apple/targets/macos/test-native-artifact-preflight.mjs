import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import {
  ArtifactProvenanceError,
  createHardMuteArtifactManifest,
  verifyHardMuteArtifactManifest,
  writeManifestAtomic,
} from './native-artifact-provenance.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const repositoryRoot = path.resolve(here, '../..')
const scratchRoot = path.join(repositoryRoot, '.scratch')
fs.mkdirSync(scratchRoot, { recursive: true })
const fixtureRoot = fs.mkdtempSync(path.join(scratchRoot, 'native-artifact-preflight-test-'))
const gate = 'GEA_TEST_AUDIO_MUTED'
const noCodeSignature = () => {}

function git(cwd, ...args) {
  const result = spawnSync('git', ['-C', cwd, ...args], { encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  return result.stdout.trim()
}

function write(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, contents)
}

function createFixture(name, { objectContainsGate = true, executableContainsGate = true } = {}) {
  const root = path.join(fixtureRoot, name)
  const dependency = path.join(root, 'dependency')
  const build = path.join(root, 'build')
  fs.mkdirSync(dependency, { recursive: true })
  fs.mkdirSync(build, { recursive: true })
  const source = path.join(dependency, 'native', 'audio_gate.h')
  const translationUnit = path.join(dependency, 'wrapper.mm')
  const object = path.join(build, 'wrapper.mm.o')
  const depfile = `${object}.d`
  const executable = path.join(root, 'Fixture.app', 'Contents', 'MacOS', 'Fixture')
  const linkSignature = path.join(build, 'link.sig')
  const manifestPath = path.join(build, 'hard-mute-artifact-provenance.json')
  write(source, `inline constexpr const char *hardMuteGate = "${gate}";\n`)
  write(translationUnit, '#include "native/audio_gate.h"\n')
  write(object, objectContainsGate
    ? Buffer.concat([Buffer.from('object\0'), Buffer.from(gate), Buffer.from('\0payload')])
    : Buffer.from('object\0payload'))
  write(executable, executableContainsGate
    ? Buffer.concat([Buffer.from('executable\0'), Buffer.from(gate), Buffer.from('\0payload')])
    : Buffer.from('executable\0payload'))
  write(depfile, `${object}: ${translationUnit} ${source}\n`)
  write(linkSignature, `compiler=fixture\nobject=${object}\n`)
  git(dependency, 'init', '-q')
  git(dependency, 'config', 'user.name', 'Artifact Preflight Test')
  git(dependency, 'config', 'user.email', 'artifact-preflight@example.invalid')
  git(dependency, 'add', '.')
  git(dependency, 'commit', '-qm', 'fixture')
  return { root, dependency, build, source, translationUnit, object, depfile, executable, linkSignature, manifestPath }
}

function assertFailure(code, operation) {
  assert.throws(operation, (error) => error instanceof ArtifactProvenanceError && error.code === code)
}

try {
  const passing = createFixture('passing')
  const manifest = createHardMuteArtifactManifest({
    executable: passing.executable,
    source: passing.source,
    linkSignature: passing.linkSignature,
    buildDirectory: passing.build,
    workingDirectory: passing.root,
    dependencyRoots: [passing.dependency],
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  writeManifestAtomic(passing.manifestPath, manifest)
  const verified = verifyHardMuteArtifactManifest({
    manifestPath: passing.manifestPath,
    executable: passing.executable,
    source: passing.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  assert.equal(verified.object.sha256, manifest.object.sha256)
  assert.equal(verified.hardMuteSource.git.revision, git(passing.dependency, 'rev-parse', 'HEAD'))

  const missingGate = createFixture('missing-gate', { objectContainsGate: false })
  assertFailure('object-hard-mute-gate-count', () => createHardMuteArtifactManifest({
    executable: missingGate.executable,
    source: missingGate.source,
    linkSignature: missingGate.linkSignature,
    buildDirectory: missingGate.build,
    workingDirectory: missingGate.root,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  const objectMismatch = createFixture('object-mismatch')
  const objectManifest = createHardMuteArtifactManifest({
    executable: objectMismatch.executable,
    source: objectMismatch.source,
    linkSignature: objectMismatch.linkSignature,
    buildDirectory: objectMismatch.build,
    workingDirectory: objectMismatch.root,
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  writeManifestAtomic(objectMismatch.manifestPath, objectManifest)
  fs.appendFileSync(objectMismatch.object, ':tampered')
  assertFailure('object-sha256-mismatch', () => verifyHardMuteArtifactManifest({
    manifestPath: objectMismatch.manifestPath,
    executable: objectMismatch.executable,
    source: objectMismatch.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  const executableMismatch = createFixture('executable-mismatch')
  const executableManifest = createHardMuteArtifactManifest({
    executable: executableMismatch.executable,
    source: executableMismatch.source,
    linkSignature: executableMismatch.linkSignature,
    buildDirectory: executableMismatch.build,
    workingDirectory: executableMismatch.root,
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  writeManifestAtomic(executableMismatch.manifestPath, executableManifest)
  fs.appendFileSync(executableMismatch.executable, ':tampered')
  assertFailure('executable-sha256-mismatch', () => verifyHardMuteArtifactManifest({
    manifestPath: executableMismatch.manifestPath,
    executable: executableMismatch.executable,
    source: executableMismatch.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  const sourceMismatch = createFixture('source-mismatch')
  const sourceManifest = createHardMuteArtifactManifest({
    executable: sourceMismatch.executable,
    source: sourceMismatch.source,
    linkSignature: sourceMismatch.linkSignature,
    buildDirectory: sourceMismatch.build,
    workingDirectory: sourceMismatch.root,
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  writeManifestAtomic(sourceMismatch.manifestPath, sourceManifest)
  fs.appendFileSync(sourceMismatch.source, '// tampered\n')
  assertFailure('hard-mute-source-sha256-mismatch', () => verifyHardMuteArtifactManifest({
    manifestPath: sourceMismatch.manifestPath,
    executable: sourceMismatch.executable,
    source: sourceMismatch.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  const revisionMismatch = createFixture('revision-mismatch')
  const revisionManifest = createHardMuteArtifactManifest({
    executable: revisionMismatch.executable,
    source: revisionMismatch.source,
    linkSignature: revisionMismatch.linkSignature,
    buildDirectory: revisionMismatch.build,
    workingDirectory: revisionMismatch.root,
    gate,
    verifyCodeSignature: noCodeSignature,
  })
  revisionManifest.dependencies[0].revision = '0'.repeat(40)
  writeManifestAtomic(revisionMismatch.manifestPath, revisionManifest)
  assertFailure('dependency-revision-mismatch', () => verifyHardMuteArtifactManifest({
    manifestPath: revisionMismatch.manifestPath,
    executable: revisionMismatch.executable,
    source: revisionMismatch.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  assertFailure('manifest-missing', () => verifyHardMuteArtifactManifest({
    manifestPath: path.join(fixtureRoot, 'missing.json'),
    executable: passing.executable,
    source: passing.source,
    gate,
    verifyCodeSignature: noCodeSignature,
  }))

  console.log('native hard-mute artifact provenance/preflight tests passed')
} finally {
  fs.rmSync(fixtureRoot, { recursive: true, force: true })
}

import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

// This module only inspects files, code-signing metadata, and Git metadata. It
// deliberately has no facility for executing the selected native artifact.
export const HARD_MUTE_PROVENANCE_SCHEMA = 'gea.apple.native-hard-mute-provenance/v1'

export class ArtifactProvenanceError extends Error {
  constructor(code, detail = '') {
    super(detail ? `${code}: ${detail}` : code)
    this.name = 'ArtifactProvenanceError'
    this.code = code
    this.detail = detail
  }
}

function fail(code, detail = '') {
  throw new ArtifactProvenanceError(code, detail)
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.length === 0) fail('invalid-manifest', `${field} must be a non-empty string`)
  return value
}

function requireObject(value, field) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail('invalid-manifest', `${field} must be an object`)
  }
  return value
}

function canonicalDirectory(directory, code = 'directory-missing') {
  let canonical
  try {
    canonical = fs.realpathSync(directory)
  } catch {
    fail(code, directory)
  }
  if (!fs.statSync(canonical).isDirectory()) fail(code, directory)
  return canonical
}

function canonicalFile(file, code = 'file-missing') {
  let canonical
  try {
    canonical = fs.realpathSync(file)
  } catch {
    fail(code, file)
  }
  if (!fs.statSync(canonical).isFile()) fail(code, file)
  return canonical
}

export function sha256File(file) {
  const hash = crypto.createHash('sha256')
  const descriptor = fs.openSync(file, 'r')
  const buffer = Buffer.allocUnsafe(1024 * 1024)
  try {
    while (true) {
      const read = fs.readSync(descriptor, buffer, 0, buffer.length, null)
      if (read === 0) break
      hash.update(buffer.subarray(0, read))
    }
  } finally {
    fs.closeSync(descriptor)
  }
  return hash.digest('hex')
}

function countBufferOccurrences(file, literal) {
  const needle = Buffer.from(literal, 'utf8')
  if (needle.length === 0) fail('invalid-gate-literal')
  const haystack = fs.readFileSync(file)
  let count = 0
  let offset = 0
  while (offset <= haystack.length - needle.length) {
    const found = haystack.indexOf(needle, offset)
    if (found < 0) break
    count += 1
    offset = found + needle.length
  }
  return count
}

function countExactCStringOccurrences(file, literal) {
  const expected = Buffer.from(literal, 'utf8')
  const contents = fs.readFileSync(file)
  let count = 0
  let start = 0
  while (start < contents.length) {
    while (start < contents.length && (contents[start] < 0x20 || contents[start] > 0x7e)) start += 1
    let end = start
    while (end < contents.length && contents[end] >= 0x20 && contents[end] <= 0x7e) end += 1
    if (end - start === expected.length && contents.subarray(start, end).equals(expected)) count += 1
    start = end + 1
  }
  return count
}

function requireSingleGateLiteral(file, literal, role, exactCString = false) {
  const count = exactCString
    ? countExactCStringOccurrences(file, literal)
    : countBufferOccurrences(file, literal)
  if (count !== 1) fail(`${role}-hard-mute-gate-count`, `expected 1, found ${count}: ${file}`)
  return count
}

function runGit(directory, args, code) {
  const result = spawnSync('git', ['-C', directory, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  if (result.status !== 0) fail(code, result.stderr.trim() || `${directory}: git ${args.join(' ')}`)
  return result.stdout.trim()
}

function repositoryForPath(target) {
  const stat = fs.statSync(target)
  const directory = stat.isDirectory() ? target : path.dirname(target)
  const root = canonicalDirectory(runGit(directory, ['rev-parse', '--show-toplevel'], 'dependency-repository-missing'))
  const revision = runGit(root, ['rev-parse', 'HEAD'], 'dependency-revision-missing')
  return { root, revision }
}

function trackedFileRecord(file, role) {
  const repository = repositoryForPath(file)
  const relativePath = path.relative(repository.root, file).split(path.sep).join('/')
  if (relativePath.startsWith('../') || path.isAbsolute(relativePath)) {
    fail(`${role}-outside-dependency-repository`, file)
  }
  const committedBlob = runGit(
    repository.root,
    ['rev-parse', `${repository.revision}:${relativePath}`],
    `${role}-not-tracked-at-dependency-revision`,
  )
  const workingBlob = runGit(repository.root, ['hash-object', file], `${role}-hash-object-failed`)
  if (workingBlob !== committedBlob) {
    fail(`${role}-does-not-match-dependency-revision`, `${relativePath} at ${repository.revision}`)
  }
  return { ...repository, relativePath, blob: committedBlob }
}

function fileRecord(file) {
  return { path: file, sha256: sha256File(file) }
}

function tokenizeMakeDependencies(text) {
  const collapsed = text.replace(/\\\r?\n/g, ' ')
  let colon = -1
  let escaped = false
  for (let index = 0; index < collapsed.length; index += 1) {
    const character = collapsed[index]
    if (escaped) {
      escaped = false
      continue
    }
    if (character === '\\') {
      escaped = true
      continue
    }
    if (character === ':') {
      colon = index
      break
    }
  }
  if (colon < 0) fail('invalid-depfile', 'missing target separator')

  const dependencies = []
  let token = ''
  escaped = false
  for (const character of collapsed.slice(colon + 1)) {
    if (escaped) {
      token += character
      escaped = false
      continue
    }
    if (character === '\\') {
      escaped = true
      continue
    }
    if (/\s/.test(character)) {
      if (token.length > 0) {
        dependencies.push(token)
        token = ''
      }
      continue
    }
    token += character
  }
  if (escaped) token += '\\'
  if (token.length > 0) dependencies.push(token)
  return dependencies
}

function dependencyPaths(depfile, workingDirectory) {
  return tokenizeMakeDependencies(fs.readFileSync(depfile, 'utf8')).map((dependency) =>
    path.normalize(path.isAbsolute(dependency) ? dependency : path.resolve(workingDirectory, dependency)),
  )
}

function walkDepfiles(directory) {
  const depfiles = []
  const visit = (current) => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && entry.name.endsWith('.o.d')) depfiles.push(full)
    }
  }
  visit(directory)
  return depfiles.sort()
}

function linkedObjects(linkSignature) {
  const objects = new Set()
  for (const line of fs.readFileSync(linkSignature, 'utf8').split(/\r?\n/)) {
    if (!line.startsWith('object=')) continue
    const candidate = line.slice('object='.length)
    if (candidate.length === 0) continue
    objects.add(path.normalize(path.isAbsolute(candidate) ? candidate : path.resolve(path.dirname(linkSignature), candidate)))
  }
  return objects
}

function findSelectedObject({ buildDirectory, source, linkSignature, workingDirectory }) {
  const canonicalSource = canonicalFile(source, 'hard-mute-source-missing')
  const linked = linkedObjects(linkSignature)
  const matches = []
  for (const depfileCandidate of walkDepfiles(buildDirectory)) {
    const dependencies = dependencyPaths(depfileCandidate, workingDirectory)
    let includesSource = false
    for (const dependency of dependencies) {
      try {
        if (fs.realpathSync(dependency) === canonicalSource) {
          includesSource = true
          break
        }
      } catch {
        // An unrelated removed dependency is not the selected source.
      }
    }
    if (!includesSource) continue
    const objectCandidate = path.normalize(depfileCandidate.slice(0, -2))
    if (!linked.has(objectCandidate)) continue
    matches.push({ depfile: depfileCandidate, object: objectCandidate, dependencies })
  }
  if (matches.length === 0) fail('hard-mute-source-not-linked', canonicalSource)
  if (matches.length !== 1) fail('hard-mute-source-linked-by-multiple-objects', matches.map(({ object }) => object).join(', '))
  const match = matches[0]
  const object = canonicalFile(match.object, 'hard-mute-object-missing')
  const depfile = canonicalFile(match.depfile, 'hard-mute-depfile-missing')
  const translationUnitCandidate = match.dependencies.find((dependency) => fs.existsSync(dependency) && fs.statSync(dependency).isFile())
  if (!translationUnitCandidate) fail('translation-unit-missing', depfile)
  const translationUnit = canonicalFile(translationUnitCandidate, 'translation-unit-missing')
  return { object, depfile, translationUnit }
}

export function defaultCodeSignatureVerifier(executable) {
  const result = spawnSync('/usr/bin/codesign', ['--verify', '--strict', executable], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  if (result.status !== 0) fail('invalid-code-signature', result.stderr.trim() || executable)
}

function dependencyRecords(paths) {
  const byRoot = new Map()
  for (const candidate of paths) {
    const canonical = canonicalDirectory(candidate, 'dependency-root-missing')
    const record = repositoryForPath(canonical)
    byRoot.set(record.root, record)
  }
  return [...byRoot.values()].sort((left, right) => left.root.localeCompare(right.root))
}

export function createHardMuteArtifactManifest(options) {
  const gate = requireString(options.gate, 'gate')
  if (!/^[\x20-\x7e]+$/.test(gate)) fail('invalid-gate-literal', 'gate must contain printable ASCII only')
  const executable = canonicalFile(options.executable, 'executable-missing')
  const source = canonicalFile(options.source, 'hard-mute-source-missing')
  const linkSignature = canonicalFile(options.linkSignature, 'link-signature-missing')
  const buildDirectory = canonicalDirectory(options.buildDirectory ?? path.dirname(linkSignature), 'build-directory-missing')
  const workingDirectory = canonicalDirectory(options.workingDirectory ?? process.cwd(), 'build-working-directory-missing')
  const verifyCodeSignature = options.verifyCodeSignature ?? defaultCodeSignatureVerifier

  verifyCodeSignature(executable)
  requireSingleGateLiteral(source, gate, 'source')
  const selected = findSelectedObject({ buildDirectory, source, linkSignature, workingDirectory })
  requireSingleGateLiteral(selected.object, gate, 'object', true)
  requireSingleGateLiteral(executable, gate, 'executable', true)

  const sourceGit = trackedFileRecord(source, 'hard-mute-source')
  const translationUnitGit = trackedFileRecord(selected.translationUnit, 'translation-unit')
  const dependencyRoots = [
    sourceGit.root,
    translationUnitGit.root,
    ...(options.dependencyRoots ?? []),
  ]

  return {
    schema: HARD_MUTE_PROVENANCE_SCHEMA,
    gate,
    buildWorkingDirectory: workingDirectory,
    hardMuteSource: { ...fileRecord(source), git: sourceGit },
    translationUnit: { ...fileRecord(selected.translationUnit), git: translationUnitGit },
    object: fileRecord(selected.object),
    depfile: fileRecord(selected.depfile),
    linkSignature: fileRecord(linkSignature),
    executable: fileRecord(executable),
    dependencies: dependencyRecords(dependencyRoots),
    codeSignatureVerified: true,
  }
}

export function writeManifestAtomic(manifestPath, manifest) {
  const destination = path.resolve(manifestPath)
  fs.mkdirSync(path.dirname(destination), { recursive: true })
  const temporary = `${destination}.tmp.${process.pid}`
  fs.writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, { flag: 'wx' })
  try {
    fs.renameSync(temporary, destination)
  } catch (error) {
    fs.rmSync(temporary, { force: true })
    throw error
  }
  return destination
}

function assertFileHash(record, role) {
  const value = requireObject(record, role)
  const file = canonicalFile(requireString(value.path, `${role}.path`), `${role}-missing`)
  const expected = requireString(value.sha256, `${role}.sha256`)
  const actual = sha256File(file)
  if (actual !== expected) fail(`${role}-sha256-mismatch`, `${actual} != ${expected}: ${file}`)
  return file
}

function assertExpectedPath(actual, expected, role) {
  const canonicalExpected = canonicalFile(expected, `${role}-missing`)
  if (actual !== canonicalExpected) fail(`${role}-path-mismatch`, `${actual} != ${canonicalExpected}`)
}

function verifyGitFileRecord(file, record, role) {
  const git = requireObject(record, `${role}.git`)
  const current = trackedFileRecord(file, role)
  for (const field of ['root', 'revision', 'relativePath', 'blob']) {
    if (current[field] !== requireString(git[field], `${role}.git.${field}`)) {
      fail(`${role}-git-${field}-mismatch`, `${current[field]} != ${git[field]}`)
    }
  }
}

export function verifyHardMuteArtifactManifest(options) {
  const manifestPath = canonicalFile(options.manifestPath, 'manifest-missing')
  let manifest
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    fail('invalid-manifest', error.message)
  }
  requireObject(manifest, 'manifest')
  if (manifest.schema !== HARD_MUTE_PROVENANCE_SCHEMA) fail('unsupported-manifest-schema', String(manifest.schema))
  const expectedGate = requireString(options.gate, 'gate')
  if (!/^[\x20-\x7e]+$/.test(expectedGate)) fail('invalid-gate-literal', 'gate must contain printable ASCII only')
  if (manifest.gate !== expectedGate) fail('hard-mute-gate-mismatch', `${manifest.gate} != ${expectedGate}`)

  const source = assertFileHash(manifest.hardMuteSource, 'hard-mute-source')
  const translationUnit = assertFileHash(manifest.translationUnit, 'translation-unit')
  const object = assertFileHash(manifest.object, 'object')
  const depfile = assertFileHash(manifest.depfile, 'depfile')
  const linkSignature = assertFileHash(manifest.linkSignature, 'link-signature')
  const executable = assertFileHash(manifest.executable, 'executable')
  assertExpectedPath(source, options.source, 'hard-mute-source')
  assertExpectedPath(executable, options.executable, 'executable')

  const workingDirectory = canonicalDirectory(
    requireString(manifest.buildWorkingDirectory, 'buildWorkingDirectory'),
    'build-working-directory-missing',
  )
  const selected = findSelectedObject({
    buildDirectory: path.dirname(linkSignature),
    source,
    linkSignature,
    workingDirectory,
  })
  if (selected.object !== object) fail('linked-object-path-mismatch', `${selected.object} != ${object}`)
  if (selected.depfile !== depfile) fail('depfile-path-mismatch', `${selected.depfile} != ${depfile}`)
  if (selected.translationUnit !== translationUnit) {
    fail('translation-unit-path-mismatch', `${selected.translationUnit} != ${translationUnit}`)
  }

  requireSingleGateLiteral(source, expectedGate, 'source')
  requireSingleGateLiteral(object, expectedGate, 'object', true)
  requireSingleGateLiteral(executable, expectedGate, 'executable', true)
  verifyGitFileRecord(source, manifest.hardMuteSource.git, 'hard-mute-source')
  verifyGitFileRecord(translationUnit, manifest.translationUnit.git, 'translation-unit')

  if (!Array.isArray(manifest.dependencies) || manifest.dependencies.length === 0) {
    fail('invalid-manifest', 'dependencies must be a non-empty array')
  }
  const seenRoots = new Set()
  for (const dependency of manifest.dependencies) {
    requireObject(dependency, 'dependency')
    const root = canonicalDirectory(requireString(dependency.root, 'dependency.root'), 'dependency-root-missing')
    if (seenRoots.has(root)) fail('invalid-manifest', `duplicate dependency root: ${root}`)
    seenRoots.add(root)
    const revision = runGit(root, ['rev-parse', 'HEAD'], 'dependency-revision-missing')
    const expectedRevision = requireString(dependency.revision, 'dependency.revision')
    if (revision !== expectedRevision) {
      fail('dependency-revision-mismatch', `${root}: ${revision} != ${expectedRevision}`)
    }
  }

  const verifyCodeSignature = options.verifyCodeSignature ?? defaultCodeSignatureVerifier
  verifyCodeSignature(executable)
  if (manifest.codeSignatureVerified !== true) fail('invalid-manifest', 'codeSignatureVerified must be true')
  return manifest
}

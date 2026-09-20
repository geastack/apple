#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

const args = new Set(process.argv.slice(2))
const outArgIndex = process.argv.indexOf('--out-dir')
const outDirValue = outArgIndex >= 0 ? process.argv[outArgIndex + 1] : ''
const dryRun = args.has('--dry-run')

if (!outDirValue) {
  process.stderr.write('usage: prune-generated-modules.mjs --out-dir <generated-dir> [--dry-run]\n')
  process.exit(1)
}

const outDir = path.resolve(outDirValue)
const modulesDir = path.join(outDir, 'modules')
const sourceListPath = path.join(outDir, 'geatsc-sources.txt')
const ownedManifestPath = path.join(outDir, '.gea-owned-modules.json')

if (!fs.existsSync(modulesDir) || !fs.existsSync(sourceListPath)) {
  process.stdout.write(`${JSON.stringify({ activeFamilies: 0, keptFiles: 0, removedFiles: 0 })}\n`)
  process.exit(0)
}

const ownedModulePattern = /^(?:\d{4}_.+\.(?:cpp|hpp|types\.hpp)|__gea_data_batch_\d{4}\.cpp)$/

function familyOf(filename) {
  return filename.replace(/\.types\.hpp$|\.hpp$|\.cpp$/, '')
}

function familyFiles(family) {
  return [`${family}.cpp`, `${family}.hpp`, `${family}.types.hpp`]
}

function isInside(parent, candidate) {
  const relative = path.relative(parent, candidate)
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)
}

// A killed prior prune may have moved only part of its stale set. Restore that
// set before making a new plan; active files therefore never depend on the
// precise point at which the previous process died.
if (!dryRun) {
  for (const entry of fs.readdirSync(outDir, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith('.gea-prune-quarantine-')) continue
    const quarantine = path.join(outDir, entry.name)
    for (const filename of fs.readdirSync(quarantine)) {
      const source = path.join(quarantine, filename)
      const destination = path.join(modulesDir, filename)
      if (!fs.existsSync(destination)) fs.renameSync(source, destination)
      else fs.rmSync(source, { force: true })
    }
    fs.rmdirSync(quarantine)
  }
}

const listedSources = fs.readFileSync(sourceListPath, 'utf8').split(/\r?\n/).filter(Boolean)
const activeFamilies = new Set()
for (const source of listedSources) {
  const resolved = path.resolve(source)
  if (!fs.existsSync(resolved)) {
    throw new Error(`Refusing to prune: active source is missing: ${resolved}`)
  }
  if (path.dirname(resolved) === modulesDir && resolved.endsWith('.cpp')) {
    activeFamilies.add(familyOf(path.basename(resolved)))
  }
}

const moduleEntries = new Set(fs.readdirSync(modulesDir, { withFileTypes: true })
  .filter((entry) => entry.isFile())
  .map((entry) => entry.name))
const keptFiles = new Set()
const scanQueue = []

function keepFile(filename) {
  if (!moduleEntries.has(filename) || keptFiles.has(filename)) return
  keptFiles.add(filename)
  scanQueue.push(filename)
}

function keepFamily(family) {
  for (const filename of familyFiles(family)) keepFile(filename)
}

for (const family of activeFamilies) keepFamily(family)

// Follow local quoted includes from every active family. This is the safety
// valve for a genuinely header-only generated support family: it remains even
// though it has no entry in geatsc-sources.txt.
const includePattern = /^\s*#\s*include\s+"([^"]+)"/gm
for (let index = 0; index < scanQueue.length; index += 1) {
  const filename = scanQueue[index]
  const filePath = path.join(modulesDir, filename)
  const contents = fs.readFileSync(filePath, 'utf8')
  includePattern.lastIndex = 0
  let match
  while ((match = includePattern.exec(contents)) !== null) {
    const included = path.resolve(path.dirname(filePath), match[1])
    if (!isInside(modulesDir, included) || !fs.existsSync(included)) continue
    const includedName = path.basename(included)
    keepFile(includedName)
    keepFamily(familyOf(includedName))
  }
}

const ownedFiles = [...moduleEntries].filter((filename) => ownedModulePattern.test(filename)).sort()
const staleFiles = ownedFiles.filter((filename) => !keptFiles.has(filename))
const remainingOwnedFiles = ownedFiles.filter((filename) => keptFiles.has(filename))

const result = {
  activeFamilies: activeFamilies.size,
  keptFiles: keptFiles.size,
  removedFiles: staleFiles.length,
  staleFiles,
}

if (dryRun) {
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`)
  process.exit(0)
}

const quarantine = path.join(outDir, `.gea-prune-quarantine-${process.pid}`)
fs.mkdirSync(quarantine)
const moved = []
try {
  for (const filename of staleFiles) {
    fs.renameSync(path.join(modulesDir, filename), path.join(quarantine, filename))
    moved.push(filename)
  }

  const manifest = `${JSON.stringify({ version: 1, files: remainingOwnedFiles }, null, 2)}\n`
  const manifestTemporary = `${ownedManifestPath}.tmp.${process.pid}`
  fs.writeFileSync(manifestTemporary, manifest)
  fs.renameSync(manifestTemporary, ownedManifestPath)
  fs.rmSync(quarantine, { recursive: true, force: true })
} catch (error) {
  for (const filename of moved.reverse()) {
    const source = path.join(quarantine, filename)
    const destination = path.join(modulesDir, filename)
    if (fs.existsSync(source) && !fs.existsSync(destination)) fs.renameSync(source, destination)
  }
  fs.rmSync(quarantine, { recursive: true, force: true })
  throw error
}

process.stdout.write(`${JSON.stringify(result)}\n`)

#!/usr/bin/env node
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  ArtifactProvenanceError,
  createHardMuteArtifactManifest,
  verifyHardMuteArtifactManifest,
  writeManifestAtomic,
} from './native-artifact-provenance.mjs'

function usage() {
  process.stderr.write(
    'usage:\n' +
      '  preflight-hard-muted-artifact.mjs record --manifest <file> --executable <file> --link-signature <file> --source <file> --gate <literal> [--build-working-directory <dir>] [--dependency-root <dir> ...]\n' +
      '  preflight-hard-muted-artifact.mjs verify --manifest <file> --executable <file> --source <file> --gate <literal>\n',
  )
}

function parseArguments(argv) {
  const [command, ...rest] = argv
  if (command !== 'record' && command !== 'verify') {
    usage()
    process.exitCode = 64
    return null
  }
  const values = { command, dependencyRoots: [] }
  for (let index = 0; index < rest.length; index += 1) {
    const option = rest[index]
    const value = rest[index + 1]
    if (!option.startsWith('--') || value === undefined || value.startsWith('--')) {
      usage()
      process.exitCode = 64
      return null
    }
    index += 1
    switch (option) {
      case '--manifest': values.manifestPath = value; break
      case '--executable': values.executable = value; break
      case '--link-signature': values.linkSignature = value; break
      case '--source': values.source = value; break
      case '--gate': values.gate = value; break
      case '--build-working-directory': values.workingDirectory = value; break
      case '--dependency-root': values.dependencyRoots.push(value); break
      default:
        usage()
        process.exitCode = 64
        return null
    }
  }
  const required = command === 'record'
    ? ['manifestPath', 'executable', 'linkSignature', 'source', 'gate']
    : ['manifestPath', 'executable', 'source', 'gate']
  if (required.some((field) => !values[field])) {
    usage()
    process.exitCode = 64
    return null
  }
  return values
}

export function run(argv) {
  const options = parseArguments(argv)
  if (!options) return
  try {
    if (options.command === 'record') {
      const manifest = createHardMuteArtifactManifest(options)
      const manifestPath = writeManifestAtomic(options.manifestPath, manifest)
      process.stdout.write(`PASS artifact-provenance-recorded=${path.resolve(manifestPath)}\n`)
      process.stdout.write(`executable_sha256=${manifest.executable.sha256}\n`)
      process.stdout.write(`object_sha256=${manifest.object.sha256}\n`)
      process.stdout.write(`source_sha256=${manifest.hardMuteSource.sha256}\n`)
      for (const dependency of manifest.dependencies) {
        process.stdout.write(`dependency_revision=${dependency.root}@${dependency.revision}\n`)
      }
      return
    }
    const manifest = verifyHardMuteArtifactManifest(options)
    process.stdout.write('PASS artifact-static-hard-mute-gate=present\n')
    process.stdout.write(`executable_sha256=${manifest.executable.sha256}\n`)
    process.stdout.write(`object_sha256=${manifest.object.sha256}\n`)
    process.stdout.write(`source_sha256=${manifest.hardMuteSource.sha256}\n`)
  } catch (error) {
    if (error instanceof ArtifactProvenanceError) {
      process.stderr.write(`FAIL reason=${error.code}${error.detail ? ` detail=${JSON.stringify(error.detail)}` : ''}\n`)
      process.exitCode = 1
      return
    }
    throw error
  }
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) run(process.argv.slice(2))

#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const args = process.argv.slice(2)

function value(name) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] || '' : ''
}

const graphPath = path.resolve(value('--graph') || '')
const referencePath = path.resolve(value('--reference') || '')
if (!value('--graph') || !value('--reference')) {
  process.stderr.write('usage: check-module-graph-freshness.mjs --graph <graph.json> --reference <stamp>\n')
  process.exit(1)
}
if (!fs.existsSync(graphPath) || !fs.existsSync(referencePath)) process.exit(0)

const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'))
const graphDir = path.dirname(graphPath)
const referenceMtime = fs.statSync(referencePath).mtimeMs
const visited = new Set()

function realInputFor(module) {
  if (module?.assetSource && path.isAbsolute(module.assetSource)) return module.assetSource
  const moduleFile = module?.file
  if (!moduleFile || !path.isAbsolute(moduleFile)) return ''
  if (fs.existsSync(moduleFile)) return moduleFile
  // The native asset Vite plugin represents binary imports as virtual sibling
  // modules. The graph records the virtual id; the real binary remains the
  // generation input whose content/mtime must invalidate generated C++.
  const assetStubSuffix = '.geaassetstub.js'
  if (moduleFile.endsWith(assetStubSuffix)) {
    return moduleFile.slice(0, -assetStubSuffix.length)
  }
  return moduleFile
}

for (const module of Array.isArray(graph.modules) ? graph.modules : []) {
  const input = realInputFor(module)
  if (!input || visited.has(input)) continue
  visited.add(input)
  if (!fs.existsSync(input)) {
    process.stdout.write(`missing:${input}\n`)
    process.exit(0)
  }
  const stat = fs.statSync(input)
  if (stat.mtimeMs > referenceMtime) {
    process.stdout.write(`newer:${input}\n`)
    process.exit(0)
  }

  // Static assets are represented in the compiler graph by synthetic JS
  // modules, so their originalSource snapshot contains the URL-export module,
  // not the binary bytes. Compare the content digest captured in the graph to
  // catch restored/backdated binary changes exactly.
  if (module.assetSource && typeof module.assetSha256 === 'string') {
    const currentSha256 = crypto.createHash('sha256').update(fs.readFileSync(input)).digest('hex')
    if (currentSha256 !== module.assetSha256) {
      process.stdout.write(`content:${input}\n`)
      process.exit(0)
    }
    continue
  }

  // Most module-graph original snapshots are byte-for-byte source copies.
  // Comparing those catches checkouts/restores that preserve or backdate
  // mtimes. Some Vite plugins intentionally rewrite their "original" snapshot;
  // detect that baseline and leave those modules on the mtime path above.
  if (!module.originalSource) continue
  const snapshot = path.resolve(graphDir, module.originalSource)
  if (!fs.existsSync(snapshot)) continue
  const current = fs.readFileSync(input)
  const captured = fs.readFileSync(snapshot)
  if (current.length === captured.length && !current.equals(captured)) {
    process.stdout.write(`content:${input}\n`)
    process.exit(0)
  }
}

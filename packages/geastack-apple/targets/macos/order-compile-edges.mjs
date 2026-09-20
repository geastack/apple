#!/usr/bin/env node

import { statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { resolve } from 'node:path'

const VALID_KINDS = new Set(['c', 'cxx', 'mm'])

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0
}

export function parseCompileEdges(input) {
  if (input === '') return []

  const lines = input.endsWith('\n') ? input.slice(0, -1).split('\n') : input.split('\n')
  return lines.map((line, index) => {
    const separator = line.indexOf('\t')
    if (separator <= 0 || separator !== line.lastIndexOf('\t')) {
      throw new Error(`compile edge ${index + 1} must be one kind<TAB>source record`)
    }

    const kind = line.slice(0, separator)
    const source = line.slice(separator + 1)
    if (!VALID_KINDS.has(kind)) {
      throw new Error(`compile edge ${index + 1} has unsupported kind: ${kind}`)
    }
    if (source === '') {
      throw new Error(`compile edge ${index + 1} has an empty source path`)
    }
    return { kind, source }
  })
}

export function orderCompileEdges(edges, sizeOf = source => statSync(source).size) {
  return edges
    .map((edge, inputIndex) => ({ ...edge, inputIndex, size: sizeOf(edge.source) }))
    .sort((left, right) =>
      right.size - left.size ||
      compareText(left.source, right.source) ||
      compareText(left.kind, right.kind) ||
      left.inputIndex - right.inputIndex,
    )
    .map(({ kind, source, size }) => ({ kind, source, size }))
}

export function formatCompileEdges(edges) {
  return edges.map(({ kind, source, size }) => `${kind}\t${size}\t${source}\n`).join('')
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  let input = ''
  process.stdin.setEncoding('utf8')
  process.stdin.on('data', chunk => { input += chunk })
  process.stdin.on('end', () => {
    try {
      process.stdout.write(formatCompileEdges(orderCompileEdges(parseCompileEdges(input))))
    } catch (error) {
      process.stderr.write(`order-compile-edges: ${error.message}\n`)
      process.exitCode = 1
    }
  })
}

// Native code that packages contribute to an iOS or tvOS build, the UIKit
// counterpart of the Windows target's native-packages.mjs. A package that
// carries native code for these targets says so in its own `gea-native.json`,
// and the build picks it up without the app repeating any of it:
//
//   { "tvos": {                       (and/or "ios")
//       "sources": [...],             .m, .mm, .c, .cpp compiled into the app
//       "includeDirs": [...], "frameworks": ["Metal"], "systemLibraries": ["z"],
//       "defines": { "NAME": "value" }, "libraries": [...], "resources": [...],
//       "build": { "command": ["tools/build.sh", "{platform}"],
//                  "libraries": ["libX.a"], "resources": ["NOTICES.txt"] } } }
//
// Paths are relative to the package root. Only the packages the program uses
// count: those owning a module of the compiled module graph (the app's
// declared dependencies when there is no graph).
//
// `{platform}` in a build command is the SDK being built for: tvos,
// tvos-simulator, ios or ios-simulator.
//
// `build` is for a static library the package cannot ship prebuilt (ANGLE for
// tvOS is 600 MB and built from upstream sources). The build runs the command
// with `--out <dir>` once and caches the result under
// $GEA_NATIVE_CACHE (default ~/.geastack/cache/native), keyed by package,
// version, target and the command script's contents; its `libraries` are
// linked and its `resources` (license notices) are copied into the app bundle.

import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return null
  }
}

// The nearest enclosing directory whose package.json names a package.
function packageRootOf(file, cache) {
  let dir = path.dirname(file)
  const visited = []
  let found = ''
  for (;;) {
    if (cache.has(dir)) {
      found = cache.get(dir)
      break
    }
    visited.push(dir)
    if (readJson(path.join(dir, 'package.json'))?.name) {
      found = dir
      break
    }
    const parent = path.dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  for (const entry of visited) cache.set(entry, found)
  return found
}

function usedPackageRoots(appRoot, moduleGraphPath) {
  const roots = new Set()
  const graph = moduleGraphPath ? readJson(moduleGraphPath) : null
  if (graph && Array.isArray(graph.modules)) {
    const cache = new Map()
    for (const module of graph.modules) {
      const file = module?.file
      if (typeof file !== 'string' || !path.isAbsolute(file) || !fs.existsSync(file)) continue
      const root = packageRootOf(file, cache)
      if (root) roots.add(fs.realpathSync(root))
    }
    return roots
  }
  const manifest = readJson(path.join(appRoot, 'package.json')) || {}
  const appRequire = createRequire(path.join(appRoot, 'package.json'))
  for (const name of [...Object.keys(manifest.dependencies || {}), ...Object.keys(manifest.devDependencies || {})]) {
    try {
      roots.add(fs.realpathSync(path.dirname(appRequire.resolve(`${name}/package.json`))))
    } catch {
      // Not resolvable from the app; it contributes nothing.
    }
  }
  return roots
}

function list(value, what, where) {
  if (value === undefined) return []
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== 'string' || !entry)) {
    throw new Error(`${where}: ${what} must be a list of strings`)
  }
  return value
}

function inside(root, relative, where) {
  if (path.isAbsolute(relative) || relative.split(/[\\/]/).includes('..')) throw new Error(`${where}: ${relative} must stay inside the package`)
  return path.join(root, relative)
}

function mustExist(file, where) {
  if (!fs.existsSync(file)) throw new Error(`${where}: ${file} does not exist`)
  return file
}

// Runs a package's library build once per package version, target and script.
function buildOutputs(root, manifest, platform, build, where, log) {
  const command = list(build.command, 'build.command', where).map((part) => part.replaceAll('{platform}', platform))
  if (!command.length) throw new Error(`${where}: build.command is empty`)
  const script = mustExist(inside(root, command[0], where), where)
  const libraries = list(build.libraries, 'build.libraries', where)
  const resources = list(build.resources, 'build.resources', where)
  const key = crypto.createHash('sha256').update(fs.readFileSync(script)).update(JSON.stringify(command)).digest('hex').slice(0, 12)
  const cacheRoot = process.env.GEA_NATIVE_CACHE || path.join(os.homedir(), '.geastack', 'cache', 'native')
  const out = path.join(cacheRoot, `${manifest.name.replace(/[\\/]/g, '+')}@${manifest.version || '0'}`, `${platform}-${key}`)
  const outputs = [...libraries, ...resources].map((file) => inside(out, file, where))
  if (outputs.some((file) => !fs.existsSync(file))) {
    log(`[gea] building ${libraries.join(', ')} for ${platform} from ${manifest.name} (once; cached in ${out})`)
    const runner = /\.sh$/.test(script) ? ['bash', [script, ...command.slice(1), '--out', out]] : [script, [...command.slice(1), '--out', out]]
    // The build's own output goes to stderr: callers read this module's answer
    // from stdout.
    execFileSync(runner[0], runner[1], { cwd: root, stdio: ['ignore', 2, 'inherit'] })
    for (const file of outputs) mustExist(file, `${where} (after ${command[0]})`)
  }
  return {
    libraries: libraries.map((file) => inside(out, file, where)),
    resources: resources.map((file) => inside(out, file, where)),
  }
}

export function readUikitNativePackages({ appRoot, moduleGraphPath, target, simulator = false, log = (line) => process.stderr.write(`${line}\n`) }) {
  const result = { sources: [], includeDirs: [], frameworks: [], systemLibraries: [], defines: [], libraries: [], resources: [], packages: [] }
  const appReal = fs.realpathSync(appRoot)
  for (const root of [...usedPackageRoots(appRoot, moduleGraphPath)].sort()) {
    if (root === appReal) continue
    const descriptorFile = path.join(root, 'gea-native.json')
    if (!fs.existsSync(descriptorFile)) continue
    const descriptor = readJson(descriptorFile)
    if (!descriptor) throw new Error(`${descriptorFile} is not readable JSON`)
    const section = descriptor[target]
    if (!section) continue
    const manifest = readJson(path.join(root, 'package.json')) || {}
    const where = `${manifest.name || root} gea-native.json (${target})`
    result.packages.push(manifest.name || root)
    for (const file of list(section.sources, 'sources', where)) result.sources.push(mustExist(inside(root, file, where), where))
    for (const dir of list(section.includeDirs, 'includeDirs', where)) result.includeDirs.push(mustExist(inside(root, dir, where), where))
    for (const file of list(section.libraries, 'libraries', where)) result.libraries.push(mustExist(inside(root, file, where), where))
    for (const file of list(section.resources, 'resources', where)) result.resources.push(mustExist(inside(root, file, where), where))
    result.frameworks.push(...list(section.frameworks, 'frameworks', where))
    for (const name of list(section.systemLibraries, 'systemLibraries', where)) {
      if (!/^[A-Za-z][A-Za-z0-9_.+-]*$/.test(name)) throw new Error(`${where}: invalid system library ${name}`)
      result.systemLibraries.push(name)
    }
    for (const [name, value] of Object.entries(section.defines || {})) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error(`${where}: invalid define ${name}`)
      result.defines.push(value === true || value === '' ? name : `${name}=${value}`)
    }
    if (section.build) {
      const built = buildOutputs(root, manifest, simulator ? `${target}-simulator` : target, section.build, where, log)
      result.libraries.push(...built.libraries)
      result.resources.push(...built.resources)
    }
  }
  for (const key of Object.keys(result)) result[key] = [...new Set(result[key])]
  return result
}

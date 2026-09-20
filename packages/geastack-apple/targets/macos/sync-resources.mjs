#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'

const args = process.argv.slice(2)

function values(name) {
  const out = []
  const prefix = `${name}=`
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === name) out.push(args[index + 1] || '')
    else if (args[index].startsWith(prefix)) out.push(args[index].slice(prefix.length))
  }
  return out.filter(Boolean)
}

function value(name) {
  return values(name).at(-1) || ''
}

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

const resourcesDir = path.resolve(value('--resources-dir') || '')
const manifestPath = path.resolve(value('--manifest') || '')
const configDir = value('--config-dir') ? path.resolve(value('--config-dir')) : ''
const appDirs = values('--app-dir').map((item) => path.resolve(item))
const sharedCssDirs = values('--shared-css-dir').map((item) => path.resolve(item))

if (!value('--resources-dir') || !value('--manifest')) {
  fail('usage: sync-resources.mjs --resources-dir <dir> --manifest <file> [--config-dir <dir>] [--app-dir <dir> ...] [--shared-css-dir <dir> ...]')
}

fs.mkdirSync(resourcesDir, { recursive: true })

let changed = false

function sameFileContent(source, destination) {
  if (!fs.existsSync(destination)) return false
  const sourceStat = fs.statSync(source)
  const destinationStat = fs.statSync(destination)
  if (sourceStat.size !== destinationStat.size) return false
  return fs.readFileSync(source).equals(fs.readFileSync(destination))
}

function syncFile(source, destination) {
  if (sameFileContent(source, destination)) return
  fs.mkdirSync(path.dirname(destination), { recursive: true })
  const temporary = `${destination}.tmp.${process.pid}`
  fs.copyFileSync(source, temporary)
  fs.renameSync(temporary, destination)
  changed = true
}

function removeFile(file) {
  try {
    fs.lstatSync(file)
  } catch (error) {
    if (error?.code === 'ENOENT') return
    throw error
  }
  fs.rmSync(file, { force: true })
  changed = true
}

function isSafeBasename(value) {
  return value !== '.' && value !== '..' && path.basename(value) === value && !value.includes('/') && !value.includes('\\')
}

function walkCss(root, visit) {
  if (!root || !fs.existsSync(root)) return
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'dist') continue
    const full = path.join(root, entry.name)
    if (entry.isDirectory()) walkCss(full, visit)
    else if (entry.isFile() && entry.name.endsWith('.css')) visit(full)
  }
}

// Match the build's historical first-source-wins behavior for basename
// collisions, but keep an owned manifest so removed @font-face declarations do
// not leave stale resources in the app bundle.
const desiredFonts = new Map()
for (const root of [...appDirs, ...sharedCssDirs]) {
  walkCss(root, (cssPath) => {
    const css = fs.readFileSync(cssPath, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')
    const facePattern = /@font-face\s*\{([^}]+)\}/gi
    let face
    while ((face = facePattern.exec(css)) !== null) {
      const source = face[1].match(/src\s*:\s*url\(\s*(?:"([^"]+)"|'([^']+)'|([^)"']+))\s*\)/i)
      if (!source) continue
      const raw = (source[1] || source[2] || source[3] || '').trim()
      if (!raw || /^https?:\/\//i.test(raw) || raw.startsWith('data:')) continue
      const clean = raw.split(/[?#]/, 1)[0]
      const resolved = path.resolve(path.dirname(cssPath), clean)
      if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) continue
      const basename = path.basename(resolved)
      if (!desiredFonts.has(basename)) desiredFonts.set(basename, resolved)
    }
  })
}

let previousFonts = []
try {
  const previous = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  if (Array.isArray(previous.fonts)) {
    previousFonts = previous.fonts.filter((item) => typeof item === 'string' && isSafeBasename(item))
  }
} catch {
  // A missing/old manifest simply means there are no previously-owned fonts.
}

const fontsDir = path.join(resourcesDir, 'Fonts')
// Fonts/ is wholly owned by this stage. Removing every undesired regular entry
// also cleans resources left by builds from before the ownership manifest was
// introduced and temporary files left by a killed copy.
if (fs.existsSync(fontsDir)) {
  for (const entry of fs.readdirSync(fontsDir, { withFileTypes: true })) {
    if ((entry.isFile() || entry.isSymbolicLink()) && !desiredFonts.has(entry.name)) {
      removeFile(path.join(fontsDir, entry.name))
    }
  }
}
for (const basename of previousFonts) {
  if (!desiredFonts.has(basename) && isSafeBasename(basename)) removeFile(path.join(fontsDir, basename))
}
for (const [basename, source] of desiredFonts) {
  syncFile(source, path.join(fontsDir, basename))
}
if (fs.existsSync(fontsDir) && fs.readdirSync(fontsDir).length === 0) {
  fs.rmdirSync(fontsDir)
}

const windowConfig = path.join(resourcesDir, 'window.json')
for (const entry of fs.readdirSync(resourcesDir, { withFileTypes: true })) {
  if (entry.isFile() && /^window\.json\.tmp\.\d+$/.test(entry.name)) removeFile(path.join(resourcesDir, entry.name))
}
const configSource = configDir ? path.join(configDir, 'macos.json') : ''
if (configSource && fs.existsSync(configSource)) syncFile(configSource, windowConfig)
else removeFile(windowConfig)

const manifest = `${JSON.stringify({ fonts: [...desiredFonts.keys()].sort() }, null, 2)}\n`
fs.mkdirSync(path.dirname(manifestPath), { recursive: true })
if (!fs.existsSync(manifestPath) || fs.readFileSync(manifestPath, 'utf8') !== manifest) {
  const temporary = `${manifestPath}.tmp.${process.pid}`
  fs.writeFileSync(temporary, manifest)
  fs.renameSync(temporary, manifestPath)
}

process.stdout.write(changed ? 'changed=1\n' : 'changed=0\n')

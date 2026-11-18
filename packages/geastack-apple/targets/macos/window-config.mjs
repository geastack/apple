// The window settings the macOS main reads from Resources/window.json: an app's
// macos.json, overlaid with `gea.targets.macos.window` from its package.json
// (size, title bar, appearance, `vsync`, `fullscreen`). Returns the JSON text,
// or '' when the app configures nothing.
//
// Run directly, it writes that file: node window-config.mjs <appDir> <out>
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch {
    return null
  }
}

export function windowConfigText(appDir) {
  if (!appDir) return ''
  const file = readJson(path.join(appDir, 'macos.json'))
  const fromPackage = readJson(path.join(appDir, 'package.json'))?.gea?.targets?.macos?.window
  if (!file && !fromPackage) return ''
  const base = file && typeof file === 'object' ? file : {}
  // The main reads `window` when present, else the whole file (flat macos.json).
  const window = { ...(base.window ?? base), ...(fromPackage && typeof fromPackage === 'object' ? fromPackage : {}) }
  return `${JSON.stringify({ ...base, window }, null, 2)}\n`
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [appDir, out] = process.argv.slice(2)
  const text = windowConfigText(appDir)
  if (text) fs.writeFileSync(out, text)
  else fs.rmSync(out, { force: true })
}

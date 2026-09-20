import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// These are the compiler's shipped modules and runtime sources, not the native
// executables, PCHs, package archives, or logs a tool may have left in dist.
export function compilerInputFingerprint(root) {
  const files = []
  const visit = (directory, accepts) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(file, accepts)
      else if (entry.isFile() && accepts(entry.name)) files.push(file)
    }
  }
  visit(path.join(root, 'dist'), name => name.endsWith('.js') || name.endsWith('.d.ts'))
  // cli-emit copies these from source, so hashing only dist could reuse stale
  // runtime output after a header change. Include new runtime files as well.
  visit(path.join(root, 'src/targets/cpp/runtime'), () => true)
  files.push(path.join(root, 'package.json'))
  const hash = createHash('sha256').update('gea-compiler-inputs-v1\0')
  for (const file of files.sort()) {
    hash.update(path.relative(root, file)).update('\0').update(fs.readFileSync(file)).update('\0')
  }
  return hash.digest('hex')
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (!process.argv[2]) throw new Error('Usage: compiler-input-fingerprint.mjs <compiler-root>')
  process.stdout.write(compilerInputFingerprint(path.resolve(process.argv[2])))
}

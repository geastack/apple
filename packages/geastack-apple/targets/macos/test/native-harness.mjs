// Builds a native AppKit test against the real engine and the macOS sources it
// names, then runs it. The engine is linked whole and dead-stripped: its parts
// reach each other through the tree, so a hand-picked subset never links.
import { execFile, execFileSync } from 'node:child_process'
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs'
import { availableParallelism } from 'node:os'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const run = promisify(execFile)
const root = resolve(fileURLToPath(new URL('../../../../../', import.meta.url)))
const pkg = `${root}/node_modules/@geastack`
const main = fileURLToPath(new URL('../main/', import.meta.url))
const dist = `${root}/packages/geastack-apple/dist`

const flags = [
  '-std=c++20', '-O0', '-g0', '-ffunction-sections', '-fdata-sections',
  // The capacities and pixel format build-macos.sh gives every framework TU.
  '-DGEA_EMBEDDED_PIXEL_FORMAT=1', '-DGEA_EMBEDDED_MAX_NODES=8192', '-DGEA_EMBEDDED_MAX_IMAGES=8192',
  '-DGEA_EMBEDDED_ENABLE_VIRTUAL_KEYBOARD=0', '-DGEA_EMBEDDED_GIF_C_API',
  ...['core/include', 'core', 'host/include', 'host', 'engine', 'engine/ui', 'elements', 'elements/ui',
    'engine/vendor/stb', 'engine/vendor/AnimatedGIF'].map((dir) => `-I${pkg}/${dir}`),
  `-I${main}`,
]

// The engine reaches the host's asset loader and audio player only through
// attributes these tests never set; the real ones would pull in the whole host.
const hostStubs = `#include <string>
#include "audio.h"
extern "C" double gea_host_image_acquire_asset_path(const char *, bool *owned) {
  if (owned) *owned = false;
  return -1;
}
bool gea::platform::audio::AudioSystem::playFile(const std::string &) { return false; }
`

const cpp = (dir) => readdirSync(`${pkg}/${dir}`).filter((file) => file.endsWith('.cpp')).map((file) => `${pkg}/${dir}/${file}`)

// `test` is the test's source file, or `source` its text.
export async function runNativeTest(name, { sources = [], test, source, frameworks = [], args = [[]] }) {
  const objects = `${dist}/${name}-objects`
  mkdirSync(objects, { recursive: true })
  const units = [...cpp('engine'), ...cpp('engine/ui'), ...cpp('elements/ui'), `${pkg}/core/events.cpp`]
  const jobs = units.map((file, index) => [file, `${objects}/${index}.o`, flags])
  jobs.push([`${pkg}/engine/vendor/AnimatedGIF/AnimatedGIF.c`, `${objects}/gif.o`, ['-O0', '-DGEA_EMBEDDED_GIF_C_API']])
  writeFileSync(`${objects}/host-stubs.cpp`, hostStubs)
  jobs.push([`${objects}/host-stubs.cpp`, `${objects}/host-stubs.o`, flags])
  const width = availableParallelism()
  for (let at = 0; at < jobs.length; at += width)
    await Promise.all(jobs.slice(at, at + width).map(([file, object, options]) =>
      run(file.endsWith('.c') ? 'clang' : 'clang++', [...options, '-c', file, '-o', object])))
  const executable = `${dist}/${name}`
  execFileSync('clang++', [
    ...flags, '-fobjc-arc', '-Wl,-dead_strip',
    ...jobs.map(([, object]) => object),
    ...sources.map((file) => `${main}/${file}`),
    '-x', 'objective-c++', test ?? '-', ...['AppKit', ...frameworks].flatMap((framework) => ['-framework', framework]), '-o', executable,
  ], { input: source, stdio: [source === undefined ? 'ignore' : 'pipe', 'inherit', 'inherit'] })
  for (const argv of args) execFileSync(executable, argv, { stdio: 'inherit' })
}

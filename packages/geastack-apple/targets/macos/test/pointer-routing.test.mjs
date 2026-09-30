import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { resolve } from 'node:path'

if (process.platform !== 'darwin') {
  console.log('SKIP: pointer routing requires AppKit')
  process.exit(0)
}

const root = resolve(fileURLToPath(new URL('../../../../../', import.meta.url)))
const renderer = readFileSync(new URL('../main/macos_renderer.mm', import.meta.url), 'utf8')
// Compile the production label and press bridge unchanged, alongside the real
// engine event dispatcher. Drawing and application startup are outside this test.
function section(start, end) {
  const first = renderer.indexOf(start)
  const last = renderer.indexOf(end, first)
  assert.ok(first >= 0 && last > first, `missing renderer section: ${start}`)
  return renderer.slice(first, last)
}
const source = `
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "ui/tree_internal.h"
#include "ui/tree_state.h"
#include "events.h"
@interface GeaCanvasView : NSView
@end
@implementation GeaCanvasView
@end
${section('@interface GeaTextCell', '// Editable text field')}
${section('@interface GeaRootClickBridge', '// Flipped clip view')}
${readFileSync(new URL('./pointer-routing.mm', import.meta.url), 'utf8')}
`
const pkg = `${root}/node_modules/@geastack`
const executable = `${root}/packages/geastack-apple/dist/pointer-routing-test`
execFileSync('clang++', [
  '-std=c++20', '-fobjc-arc', '-ffunction-sections', '-fdata-sections', '-Wl,-dead_strip',
  `-I${pkg}/core/include`, `-I${pkg}/host/include`, `-I${pkg}/engine`,
  `-I${pkg}/engine/ui`, `-I${pkg}/elements`, `-I${pkg}/elements/ui`,
  ...['core', 'tree_state', 'tree_events'].map(name => `${pkg}/engine/ui/${name}.cpp`),
  `${pkg}/core/events.cpp`,
  '-x', 'objective-c++', '-', '-framework', 'AppKit', '-o', executable,
], { input: source, stdio: ['pipe', 'inherit', 'inherit'] })
for (const test of ['label', 'offset', 'controls', 'mouse']) {
  execFileSync(executable, [test], { stdio: 'inherit' })
}

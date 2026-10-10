import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runNativeTest } from './native-harness.mjs'

if (process.platform !== 'darwin') {
  console.log('SKIP: pointer routing requires AppKit')
  process.exit(0)
}

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
await runNativeTest('pointer-routing-test', { sources: ['macos_memory.cpp'], source, args: ['label', 'offset', 'controls', 'mouse'].map((test) => [test]) })

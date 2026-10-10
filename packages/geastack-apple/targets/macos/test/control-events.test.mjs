import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runNativeTest } from './native-harness.mjs'

if (process.platform !== 'darwin') {
  console.log('SKIP: control events require AppKit')
  process.exit(0)
}

// The production content view, unchanged, beside the real renderer: keyboard
// and text input reach Gea's document listeners, and controls publish their
// live bounds. The window, app delegate and run loop are outside this test.
const app = readFileSync(new URL('../main/macos_main.mm', import.meta.url), 'utf8')
const first = app.indexOf('// App-owned controls consume ordinary Gea events.')
const last = app.indexOf('\n@end\n', app.indexOf('@implementation GeaContentView'))
assert.ok(first >= 0 && last > first, 'missing GeaContentView in macos_main.mm')
const source = `
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include "press_bridge.h"
#include "ui/document.h"
#include "ui/node.h"
#include "ui/tree_internal.h"
#include <algorithm>
#include <cstring>
${app.slice(first, last + 5)}
${readFileSync(new URL('./control-events.mm', import.meta.url), 'utf8')}
`
await runNativeTest('control-events-test', {
  sources: ['macos_renderer.mm', 'canvas_view.mm', 'press_bridge.mm', 'image_bridge.mm', 'color_convert.mm', 'font_registry.mm', 'macos_timers.mm', 'macos_display.mm', 'macos_sensors.cpp', 'macos_memory.cpp'],
  source,
  frameworks: ['GameController', 'QuartzCore', 'CoreImage'],
})

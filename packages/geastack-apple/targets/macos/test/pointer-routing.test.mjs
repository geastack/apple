import { readFileSync } from 'node:fs'
import { runNativeTest } from './native-harness.mjs'

if (process.platform !== 'darwin') {
  console.log('SKIP: pointer routing requires AppKit')
  process.exit(0)
}

// The production renderer is linked unchanged, alongside the real engine event
// dispatcher. The test declares only the interfaces it drives; drawing and
// application startup are outside this test.
const source = `
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "ui/tree_internal.h"
#include "events.h"
#include "canvas_view.h"
namespace gea::macos::thermalright { bool enabled() { return false; } }
@interface GeaNativeBinding : NSObject
- (instancetype)initWithNode:(int)node;
@end
@interface GeaLabelTextField : NSTextField
@end
@interface GeaRootClickBridge : NSObject <NSGestureRecognizerDelegate>
@property(nonatomic, weak) NSView *rootView;
@property(nonatomic, assign) int pressedNodeId;
@property(nonatomic, assign) int originX;
@property(nonatomic, assign) int originY;
- (void)fire:(NSGestureRecognizer *)gr;
@end
${readFileSync(new URL('./pointer-routing.mm', import.meta.url), 'utf8')}
`
await runNativeTest('pointer-routing-test', {
  sources: ['macos_renderer.mm', 'canvas_view.mm', 'press_bridge.mm', 'image_bridge.mm', 'color_convert.mm', 'font_registry.mm', 'macos_timers.mm', 'macos_display.mm', 'macos_sensors.cpp', 'macos_memory.cpp'],
  frameworks: ['QuartzCore', 'CoreImage'],
  source,
  args: ['label', 'offset', 'controls', 'mouse'].map((test) => [test]),
})

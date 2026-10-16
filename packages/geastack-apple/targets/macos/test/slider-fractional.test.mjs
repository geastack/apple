import { runNativeTest } from './native-harness.mjs'
if (process.platform !== 'darwin') process.exit(0)
await runNativeTest('slider-fractional-test', {
  sources: ['macos_renderer.mm', 'canvas_view.mm', 'press_bridge.mm', 'image_bridge.mm', 'color_convert.mm', 'font_registry.mm', 'macos_timers.mm', 'macos_display.mm', 'macos_sensors.cpp', 'macos_memory.cpp'],
  frameworks: ['QuartzCore', 'CoreImage'],
  source: String.raw`
#import <AppKit/AppKit.h>
#include "ui/tree_internal.h"
#include "ui/node.h"
#include "macos_renderer.h"
#include <cassert>
#include <cmath>
#include <cstdio>
// This offscreen control fixture has no external HID display capability.
namespace gea::macos::thermalright { bool enabled() { return false; } }
@interface NSSlider (GeaTestAction)
- (void)geaChanged:(id)sender;
@end
static NSSlider *findSlider(NSView *view) {
 if ([view isKindOfClass:[NSSlider class]]) return (NSSlider *)view;
 for (NSView *child in view.subviews) if (auto *found=findSlider(child)) return found;
 return nil;
}
static void assertNoActivation() {
 // AppKit may initialize NSApp lazily while constructing a real control.
 assert(!NSApp.active); assert(NSApp.windows.count==0);
 assert(NSApp.keyWindow==nil && NSApp.mainWindow==nil);
}
int main() { @autoreleasepool {
 assert(NSApp == nil); assertNoActivation();
 using namespace gea::embedded::ui;
 auto &tree=Tree::instance();
 int root=tree.createView(), id=tree.createView();
 tree.setParent(id,root); NodeHandle(id).setTagName("input");
 tree.setAttribute(id,"type","range");
 tree.node(root).layout.width=200; tree.node(root).layout.height=100;
 tree.node(id).layout.width=180; tree.node(id).layout.height=28;
 NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,200,100)];
 auto &renderer=gea::macos::MacosRenderer::instance();
 int inputs=0; tree.setEventListener(id,"input",[&](auto &event){
  assert(event.currentTargetId==id); ++inputs;
 });
 auto configure=[&](const char *min,const char *max,const char *step) {
  tree.setAttribute(id,"min",min); tree.setAttribute(id,"max",max);
  tree.setAttribute(id,"step",step); tree.setAttribute(id,"value","0");
  renderer.sync(host,root);
 };
 auto check=[&](double raw,double expected) {
  NSSlider *slider=findSlider(host); assert(slider);
  assert([NSStringFromClass(slider.class) isEqualToString:@"GeaSlider"]);
  int before=inputs; slider.doubleValue=raw; [slider geaChanged:slider];
  double actual=std::stod(tree.getAttribute(id,"value"));
  if (std::abs(actual-expected)>1e-10) {
   std::fprintf(stderr,"slider raw %.17g expected %.17g actual %.17g\n",raw,expected,actual); std::abort();
  }
  assert(inputs==before+1); assertNoActivation();
 };
 configure("-1","1","0.01"); check(-0.01,-0.01); check(-0.66,-0.66); check(0.25,0.25);
 check(-3,-1); check(3,1);
 configure("-120","12","0.5"); check(-54.5,-54.5); check(-54.74,-54.5); check(-54.76,-55);
 configure("0.05","0.95","0.1"); check(0.26,0.25); check(0.95,0.95);
 configure("0","0.95","0.1"); check(0.95,0.9);
 configure("-1","1","any"); check(-0.123456789,-0.123456789);
 configure("0","100",""); check(75.4,75); check(75.6,76);
 renderer.teardown(); assertNoActivation();
 std::puts("PASS signed fractional slider, step/clamp, unsigned compatibility; no application/window activation or input.");
}}
`,
})

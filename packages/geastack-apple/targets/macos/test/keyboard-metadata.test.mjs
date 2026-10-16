import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runNativeTest } from './native-harness.mjs'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url' 
if (process.platform !== 'darwin') process.exit(0)
// Verify the published native declaration and the built plugin read the same
// real carrier fields; no `any`, browser alias or reconstructed record.
const apple = fileURLToPath(new URL('../../../../../', import.meta.url))
const packages = process.env.GEA_NATIVE_TEST_PACKAGES_ROOT ?? resolve(apple, '../core/packages')
const pluginRoot = resolve(packages, 'geatsc-plugin-gea')
const require = createRequire(resolve(pluginRoot, 'package.json'))
const ts = require('typescript')
const { createGeaHostShims } = await import(pathToFileURL(resolve(pluginRoot, 'dist/host-shims.js')))
const declaration = resolve(packages, 'core/index.d.ts')
const program = ts.createProgram([declaration], { strict: true, skipLibCheck: true })
const checker = program.getTypeChecker(), source = program.getSourceFile(declaration)
const symbol = checker.getExportsOfModule(checker.getSymbolAtLocation(source)).find(s => s.name === 'KeyEvent')
const keyType = checker.getDeclaredTypeOfSymbol(symbol), shims = createGeaHostShims()
assert.equal(shims.nativeTypes.KeyEvent, 'gea::framework::events::PointerEvent')
for (const member of ['key', 'code', 'altKey', 'ctrlKey', 'metaKey', 'shiftKey', 'repeat', 'isComposing', 'defaultPrevented']) {
 const property = checker.getPropertyOfType(keyType, member)
 assert.ok(property, member)
 const type = checker.getTypeOfSymbolAtLocation(property, source)
 assert.equal(type.flags & ts.TypeFlags.Any, 0, member)
 const nativeType = ['key', 'code'].includes(member) ? 'std::string' : 'bool'
 assert.ok(shims.nativeMemberPropertyGetters[member].some(row => row.receiverTypes.includes('KeyEvent') && row.returnType === nativeType && row.emit === (member === 'defaultPrevented' ? 'static_cast<bool>(({receiver}).defaultPrevented)' : `(({receiver}).${member})`)), member)
}
const app = readFileSync(new URL('../main/macos_main.mm', import.meta.url), 'utf8')
const first = app.indexOf('// App-owned controls consume ordinary Gea events.')
const last = app.indexOf('\n@end\n', app.indexOf('@implementation GeaContentView'))
assert.ok(first >= 0 && last > first)
await runNativeTest('keyboard-metadata-test', {
 sources: ['macos_renderer.mm', 'canvas_view.mm', 'press_bridge.mm', 'image_bridge.mm', 'color_convert.mm', 'font_registry.mm', 'macos_timers.mm', 'macos_display.mm', 'macos_sensors.cpp', 'macos_memory.cpp'],
 frameworks: ['GameController', 'QuartzCore', 'CoreImage'],
 source: String.raw`
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include "macos_renderer.h"
#include "press_bridge.h"
#include "ui/document.h"
#include "ui/node.h"
#include "ui/tree_internal.h"
#include <algorithm>
#include <cstring>
#include <cassert>
#include <cstdio>
// External HID display is unavailable in this offscreen keyboard fixture.
namespace gea::macos::thermalright { bool enabled() { return false; } }
` + app.slice(first, last + 5) + String.raw`
// Native default-navigation routing is observed without constructing an
// NSWindow. This checks selector/next-responder routing, not OS focus.
@interface GeaKeyWindowSpy : NSObject
@property(nonatomic) int nextCount;
@property(nonatomic) int previousCount;
@end
@implementation GeaKeyWindowSpy
- (void)selectNextKeyView:(id)sender { (void)sender;++_nextCount; }
- (void)selectPreviousKeyView:(id)sender { (void)sender;++_previousCount; }
@end
@interface GeaKeyViewSpy : GeaContentView
@property(nonatomic,strong) GeaKeyWindowSpy *keyWindowSpy;
@end
@implementation GeaKeyViewSpy
- (NSWindow *)window { return (NSWindow *)self.keyWindowSpy; }
@end
@interface GeaKeyFallback : NSResponder
@property(nonatomic) int count;
@end
@implementation GeaKeyFallback
- (void)keyDown:(NSEvent *)event { (void)event;++_count; }
@end
static void noActivation() {
 assert(!NSApp.active && NSApp.windows.count==0);
 assert(NSApp.keyWindow==nil && NSApp.mainWindow==nil);
}
static NSEvent *key(NSEventType type, unsigned short physical, NSString *text,
 NSEventModifierFlags flags=0, bool repeat=false) {
 return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags
 timestamp:0 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text
 isARepeat:repeat keyCode:physical];
}
int main() { @autoreleasepool {
 noActivation(); using namespace gea::embedded::ui;
 auto &tree=Tree::instance(); int root=tree.createView();
 tree.setAttribute(root,"data-gea-inputs","true");
 GeaContentView *view=[[GeaContentView alloc] initWithFrame:NSZeroRect];
 gea::framework::events::PointerEvent observed; int downs=0,ups=0,plays=0,undo=0,inputs=0;
 tree.setEventListener(root,"input",[&](auto &){++inputs;});
 setDocumentEventListener("keydown",[&](auto &e){
  observed=e; ++downs;
  bool editor=e.target.id()!=root;
  if (!editor && !e.isComposing && !e.repeat) {
   if(e.key==" "&&!e.metaKey&&!e.ctrlKey&&!e.altKey)++plays;
   if(e.key=="z"&&e.metaKey&&!e.altKey)++undo;
  }
  e.preventDefault();
 });
 setDocumentEventListener("keyup",[&](auto &e){observed=e;++ups;});
 [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(downs==1 && plays==1 && inputs==0);
 assert(observed.key==" " && observed.code=="Space" && observed.keyCode==32);
 assert(!observed.repeat&&!observed.isComposing&&!observed.metaKey);
 assert(observed.target.id()==root);
 [view keyDown:key(NSEventTypeKeyDown,6,@"z",NSEventModifierFlagCommand)];
 assert(undo==1&&observed.key=="z"&&observed.code=="KeyZ"&&observed.keyCode==90&&observed.metaKey);
 [view keyDown:key(NSEventTypeKeyDown,123,@"",NSEventModifierFlagShift|NSEventModifierFlagControl|NSEventModifierFlagOption,true)];
 assert(observed.key=="ArrowLeft"&&observed.code=="ArrowLeft"&&observed.keyCode==37);
 assert(observed.shiftKey&&observed.ctrlKey&&observed.altKey&&observed.repeat&&!observed.metaKey);
 [view keyUp:key(NSEventTypeKeyUp,6,@"z",NSEventModifierFlagCommand)];
 assert(ups==1&&observed.metaKey&&observed.code=="KeyZ");
 [view setMarkedText:@"あ" selectedRange:NSMakeRange(1,0) replacementRange:NSMakeRange(NSNotFound,0)];
 [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(observed.isComposing&&plays==1&&inputs==0&&[view hasMarkedText]);
 [view unmarkText];
 int input=tree.createView(); tree.setParent(input,root); NodeHandle(input).setTagName("input");
 tree.setActiveInput(input);
 [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(observed.target.id()==input&&plays==1&&inputs==0);
 tree.setActiveInput(-1);
 [view keyDown:key(NSEventTypeKeyDown,49,@" ",0,true)]; assert(plays==1);
 resetDocumentEventListeners();
 int selects=0;
 setDocumentEventListener("keydown",[&](auto &e){assert(e.keyCode==1001);++selects;});
 [view keyDown:key(NSEventTypeKeyDown,0,@"a",NSEventModifierFlagCommand)];
 assert(selects==1); // unprevented legacy select-all must not interpret/echo
 resetDocumentEventListeners();
 // A regular mounted native root needs no private app-owned-editor marker.
 tree.setAttribute(root,"data-gea-inputs","false");
 tree.mount(root,200,100); int nodeDowns=0,documentDowns=0; bool stop=false;
 gea::framework::events::PointerEvent *nodeEvent=nullptr;
 const auto workspaceKey=tree.setEventListener(root,"keydown",[&](auto &e){
  assert(e.code=="Space");++nodeDowns;nodeEvent=&e;e.preventDefault();if(stop)e.stopPropagation();
 });
 setDocumentEventListener("keydown",[&](auto &e){
  assert(&e==nodeEvent&&e.defaultPrevented&&e.target.id()==root);++documentDowns;
 });
 [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(nodeDowns==1&&documentDowns==1&&view.acceptsFirstResponder);
 stop=true; [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(nodeDowns==2&&documentDowns==1);
 int region=tree.createView();tree.setParent(region,root);int regionDowns=0;
 tree.setEventListener(region,"keydown",[&](auto &e){assert(e.target.id()==region);++regionDowns;});
 // Headless: no window or native responder, so name the focused node directly.
 tree.setActiveInput(region);
 [view keyDown:key(NSEventTypeKeyDown,49,@" ")];
 assert(regionDowns==1&&nodeDowns==3&&documentDowns==1);
 tree.setActiveInput(-1);
 resetDocumentEventListeners();
 assert(tree.removeEventListener(root,"keydown",workspaceKey));
 GeaKeyViewSpy *defaults=[[GeaKeyViewSpy alloc] initWithFrame:NSZeroRect];
 defaults.keyWindowSpy=[GeaKeyWindowSpy new];
 GeaKeyFallback *fallback=[GeaKeyFallback new];defaults.nextResponder=fallback;
 [defaults keyDown:key(NSEventTypeKeyDown,48,@"\t")];
 [defaults keyDown:key(NSEventTypeKeyDown,48,@"\t",NSEventModifierFlagShift)];
 assert(defaults.keyWindowSpy.nextCount==1&&defaults.keyWindowSpy.previousCount==1);
 [defaults keyDown:key(NSEventTypeKeyDown,6,@"z",NSEventModifierFlagCommand)];
 assert(fallback.count==1);
 tree.setEventListener(root,"keydown",[](auto &e){e.preventDefault();});
 [defaults keyDown:key(NSEventTypeKeyDown,48,@"\t")];
 assert(defaults.keyWindowSpy.nextCount==1);
 defaults.keyWindowSpy=nil;defaults.nextResponder=nil; // restore real nil window before NSView teardown
 noActivation();
 std::puts("PASS native typed keyboard metadata, composition/editor guards, CmdZ/Space and mounted-root routing; no activation/global input.");
}}
`,
})

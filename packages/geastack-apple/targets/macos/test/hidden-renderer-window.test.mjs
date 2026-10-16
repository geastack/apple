import assert from 'node:assert/strict'
import {readFileSync,writeFileSync} from 'node:fs'
import {runNativeTest} from './native-harness.mjs'
if(process.platform!=='darwin')process.exit(0)
// Compile only; this test does not run the built executable.
const app=readFileSync(new URL('../main/macos_main.mm',import.meta.url),'utf8')
const first=app.indexOf('// App-owned controls consume ordinary Gea events.')
const last=app.indexOf('\n@end\n',app.indexOf('@implementation GeaContentView'))
assert.ok(first>=0&&last>first)
const source=String.raw`
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#include "macos_background_test.h"
#include "macos_renderer.h"
#include "press_bridge.h"
#include "ui/document.h"
#include "ui/node.h"
#include "ui/tree_internal.h"
#include <algorithm>
#include <cstring>
#include <cassert>
#include <cstdio>
#include <unistd.h>
namespace gea::macos::thermalright { bool enabled(){return false;} }
`+app.slice(first,last+5)+String.raw`
@interface NeverFrontWindow:NSWindow
@end
@implementation NeverFrontWindow
- (BOOL)canBecomeKeyWindow{return NO;}
- (BOOL)canBecomeMainWindow{return NO;}
- (void)makeKeyAndOrderFront:(id)sender{gea::macos::background_test::refuse("makeKeyAndOrderFront forbidden");}
- (void)makeKeyWindow{gea::macos::background_test::refuse("makeKeyWindow forbidden");}
- (void)makeMainWindow{gea::macos::background_test::refuse("makeMainWindow forbidden");}
- (void)orderFront:(id)sender{gea::macos::background_test::refuse("orderFront forbidden");}
- (void)orderFrontRegardless{gea::macos::background_test::refuse("orderFrontRegardless forbidden");}
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other{gea::macos::background_test::refuse("orderWindow forbidden");}
@end
static NSButton*buttonIn(NSView*v){if([v isKindOfClass:NSButton.class])return(NSButton*)v;for(NSView*c in v.subviews)if(auto*b=buttonIn(c))return b;return nil;}
static void invariants(NSWindow*w){gea::macos::background_test::checkApplication(NSApp);assert(w&&!w.visible&&!w.keyWindow&&!w.mainWindow);assert(!NSApp.keyWindow&&!NSApp.mainWindow);}
int main(){@autoreleasepool{
 alarm(12);
 if(!gea::macos::background_test::enabled())gea::macos::background_test::refuse("explicit test mode required");
 const char*audio=getenv("GEA_AUDIO_DISABLED");if(!audio||strcmp(audio,"1"))gea::macos::background_test::refuse("audio fence required before NSApplication");
 const pid_t before=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
 const NSPoint pointerBefore=NSEvent.mouseLocation;
 NSApplication*app=NSApplication.sharedApplication;gea::macos::background_test::configure(app);
 NeverFrontWindow*w=[[NeverFrontWindow alloc]initWithContentRect:NSMakeRect(0,0,640,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 w.releasedWhenClosed=NO;
 GeaContentView*view=[[GeaContentView alloc]initWithFrame:NSMakeRect(0,0,640,400)];w.contentView=view;
 auto&tree=gea::embedded::ui::Tree::instance();int root=tree.createView(),node=tree.createButton();tree.setParent(node,root);
 // Mount recomputes layout from style; direct writes to layout are outputs,
 // not declarations, and are intentionally discarded by the real layout pass.
 using gea::embedded::ui::Property;
 tree.setStyle(root,Property::Width,640);tree.setStyle(root,Property::Height,400);
 tree.setStyle(node,Property::Width,160);tree.setStyle(node,Property::Height,40);
 tree.setText(node,"Native method");tree.mount(root,640,400);assert(tree.node(node).layout.width==160&&tree.node(node).layout.height==40);gea::macos::MacosRenderer::instance().sync(view,root);
 gea::macos::background_test::present(w);invariants(w);
 int keys=0,downs=0,ups=0,clicks=0;
 tree.setEventListener(root,"keydown",[&](auto&e){if(e.key==" "){++keys;e.preventDefault();}});
 tree.setEventListener(node,"pointerdown",[&](auto&){++downs;});tree.setEventListener(node,"pointerup",[&](auto&){++ups;});tree.setEventListener(node,"click",[&](auto&){++clicks;});
 NSEvent*key=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:w.windowNumber context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
 [view keyDown:key];assert(keys==1);invariants(w);
 NSButton*b=buttonIn(view);std::fprintf(stderr,"mounted button: found=%d window=%d hidden=%d width=%g height=%g\n",b!=nil,b.window==w,(int)b.hidden,b.bounds.size.width,b.bounds.size.height);assert(b&&b.window==w&&!b.hidden&&b.bounds.size.width==160&&b.bounds.size.height==40);
 NSPoint local=NSMakePoint(NSMidX(b.bounds),NSMidY(b.bounds)),inView=[b convertPoint:local toView:view],inWindow=[b convertPoint:local toView:nil];
 NSView*hit=[view hitTest:inView];assert(hit==b||[hit isDescendantOf:b]);
 NSEvent*down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:inWindow modifierFlags:0 timestamp:1 windowNumber:w.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
 NSEvent*up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:inWindow modifierFlags:0 timestamp:1.01 windowNumber:w.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
 std::fprintf(stderr,"event ownership: windowNumber=%ld downNumber=%ld upNumber=%ld downWindow=%p upWindow=%p owned=%p\n",(long)w.windowNumber,(long)down.windowNumber,(long)up.windowNumber,down.window,up.window,w);assert(w.windowNumber>0&&down.window==w&&up.window==w);
 // This is only the owned application's local queue, never CGEvent/global input.
 [app postEvent:up atStart:NO];[b mouseDown:down];invariants(w);
 assert(downs==1&&ups==1&&clicks==1);
 NSBitmapImageRep*rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];assert(rep);[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
 assert(rep.pixelsWide>0&&rep.pixelsHigh>0);
 const unsigned char*pixels=rep.bitmapData;assert(pixels&&rep.bitsPerSample==8&&rep.samplesPerPixel>=3);bool varied=false;
 for(NSInteger y=0;y<rep.pixelsHigh&&!varied;++y)for(NSInteger x=0;x<rep.pixelsWide;++x){const auto*q=pixels+y*rep.bytesPerRow+x*rep.samplesPerPixel;if(q[0]!=pixels[0]||q[1]!=pixels[1]||q[2]!=pixels[2]){varied=true;break;}}
 assert(varied);NSData*png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];assert(png.length>0);
 const char*out=getenv("GEA_NATIVE_SNAPSHOT");if(out){NSString*p=[NSString stringWithUTF8String:out];assert(getenv("GEA_NATIVE_SNAPSHOT_DIR")&&[p hasPrefix:[[NSString stringWithUTF8String:getenv("GEA_NATIVE_SNAPSHOT_DIR")]stringByAppendingString:@"/hidden-renderer-"]]&&![p containsString:@"/../"]);assert(![[NSFileManager defaultManager]fileExistsAtPath:p]);assert([png writeToFile:p options:NSDataWritingWithoutOverwriting error:nil]);}
 invariants(w);const NSPoint pointerAfter=NSEvent.mouseLocation;const pid_t after=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
 printf("{\"scope\":\"real GeaContentView renderer/local native tracking only\",\"keys\":%d,\"downs\":%d,\"ups\":%d,\"clicks\":%d,\"width\":%ld,\"height\":%ld,\"pngBytes\":%lu,\"foregroundBefore\":%d,\"foregroundAfter\":%d,\"pointerUnchanged\":%s,\"active\":false,\"visible\":false,\"key\":false,\"main\":false}\n",keys,downs,ups,clicks,(long)rep.pixelsWide,(long)rep.pixelsHigh,(unsigned long)png.length,before,after,NSEqualPoints(pointerBefore,pointerAfter)?"true":"false");
 return 0;
}}
`
writeFileSync(new URL('../../../dist/hidden-renderer-window-source.mm',import.meta.url),source)
await runNativeTest('hidden-renderer-window-test',{sources:['macos_renderer.mm','canvas_view.mm','press_bridge.mm','image_bridge.mm','color_convert.mm','font_registry.mm','macos_timers.mm','macos_display.mm','macos_sensors.cpp','macos_memory.cpp'],frameworks:['GameController','QuartzCore','CoreImage'],source,args:[]})
console.log('Compiled only; the hidden renderer test executable was not run.')

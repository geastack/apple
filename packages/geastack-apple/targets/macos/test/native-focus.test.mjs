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
#include "ui/document.h"
#include "ui/node.h"
#include "ui/tree_internal.h"
@interface NSTextField(FocusEndTest)
-(void)controlTextDidBeginEditing:(NSNotification*)note;
-(void)controlTextDidChange:(NSNotification*)note;
-(void)controlTextDidEndEditing:(NSNotification*)note;
@end
#include <algorithm>
#include <cstring>
#include <cassert>
#include <cstdio>
#include <unistd.h>
namespace gea::macos::thermalright {bool enabled(){return false;}}
`+app.slice(first,last+5)+String.raw`
@interface FocusNeverActiveApplication:NSApplication @end
@implementation FocusNeverActiveApplication
-(BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p {if(p!=NSApplicationActivationPolicyProhibited)gea::macos::background_test::refuse("nonprohibited policy");return[super setActivationPolicy:p];}
-(void)activateIgnoringOtherApps:(BOOL)flag {(void)flag;gea::macos::background_test::refuse("activation refused");}
-(void)activate {gea::macos::background_test::refuse("activation refused");}
-(void)unhide:(id)sender {(void)sender;gea::macos::background_test::refuse("unhide refused");}
-(void)unhideWithoutActivation {gea::macos::background_test::refuse("unhide refused");}
@end
@interface FocusNeverFrontWindow:NSWindow @end
@implementation FocusNeverFrontWindow
-(BOOL)canBecomeKeyWindow{return NO;}
-(BOOL)canBecomeMainWindow{return NO;}
-(void)makeKeyAndOrderFront:(id)sender {(void)sender;gea::macos::background_test::refuse("makekey/front refused");}
-(void)makeKeyWindow {gea::macos::background_test::refuse("key refused");}
-(void)makeMainWindow {gea::macos::background_test::refuse("main refused");}
-(void)orderFront:(id)sender {(void)sender;gea::macos::background_test::refuse("front refused");}
-(void)orderFrontRegardless {gea::macos::background_test::refuse("front refused");}
-(void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)other {(void)place;(void)other;gea::macos::background_test::refuse("order refused");}
@end
static void invariant(NSWindow*owned){assert(NSApp.activationPolicy==NSApplicationActivationPolicyProhibited&&!NSApp.active&&!NSApp.keyWindow&&!NSApp.mainWindow);unsigned internal=0;for(NSWindow*w in NSApp.windows){assert(!w.visible&&!w.keyWindow&&!w.mainWindow);if(w==owned)continue;assert([NSStringFromClass(w.class)isEqualToString:@"TUINSWindow"]&&++internal<=1);}if(owned)assert([NSApp.windows containsObject:owned]&&!owned.visible&&!owned.keyWindow&&!owned.mainWindow);}
static NSTextField*field(NSView*v){if([v isKindOfClass:NSTextField.class]&&((NSTextField*)v).editable)return(NSTextField*)v;for(NSView*c in v.subviews)if(auto*f=field(c))return f;return nil;}
template<class D>static int activeId(D&d){if constexpr(requires{d.activeElement();})return d.activeElement().id();else return -404;}
int main(){@autoreleasepool{alarm(12);if(!gea::macos::background_test::enabled())gea::macos::background_test::refuse("explicit background mode required");const char*a=getenv("GEA_AUDIO_DISABLED");if(!a||strcmp(a,"1"))gea::macos::background_test::refuse("audio fence required");assert(NSApp==nil);auto*app=[FocusNeverActiveApplication sharedApplication];assert([app isKindOfClass:FocusNeverActiveApplication.class]);if(app.activationPolicy!=NSApplicationActivationPolicyProhibited)[app setActivationPolicy:NSApplicationActivationPolicyProhibited];invariant(nil);
 FocusNeverFrontWindow*w=[[FocusNeverFrontWindow alloc]initWithContentRect:NSMakeRect(0,0,640,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;GeaContentView*host=[[GeaContentView alloc]initWithFrame:NSMakeRect(0,0,640,400)];w.contentView=host;invariant(w);
 using namespace gea::embedded::ui;auto&t=Tree::instance();auto&d=Document::instance();t.clear();auto root=d.createView();auto input=d.createElement("input");input.setAttribute("type","text");input.setAttribute("id","native-focus-input");root.style().width(640);root.style().height(400);input.style().width(180);input.style().height(32);root.appendChild(input);d.mount(root,640,400);auto&r=gea::macos::MacosRenderer::instance();r.sync(host,root.id());auto*f=field(host);assert(f&&f.window==w&&!f.hidden);invariant(w);
 int focusIns=0,focusOuts=0;t.setEventListener(input.id(),"focusin",[&](auto&event){assert(std::string(event.typeName())=="focusin");assert(activeId(d)==input.id());++focusIns;});t.setEventListener(input.id(),"focusout",[&](auto&event){assert(std::string(event.typeName())=="focusout");++focusOuts;});assert([w makeFirstResponder:f]);assert(focusIns==1&&focusOuts==0);assert(w.firstResponder==f||w.firstResponder==f.currentEditor);invariant(w);fprintf(stderr,"actual native focus expected=%d tree=%d document=%d\n",input.id(),t.activeInputId(),activeId(d));assert(t.activeInputId()==input.id());assert(activeId(d)==input.id());
 // Native blur cannot be forged by a late old root callback after child focus.
 gea::macos::nativeRootFocusChanged(host,false,-1);assert(activeId(d)==input.id());
 assert([w makeFirstResponder:nil]);invariant(w);assert(activeId(d)==-1);input.focus();invariant(w);assert(w.firstResponder==f||w.firstResponder==f.currentEditor);assert(activeId(d)==input.id());input.blur();invariant(w);assert(activeId(d)==-1);assert(focusIns==2&&focusOuts==2);
 root.focus();invariant(w);assert(w.firstResponder==host&&activeId(d)==root.id());root.blur();invariant(w);assert(activeId(d)==-1);
 input.focus();invariant(w);int staleChanges=0;t.setEventListener(input.id(),"change",[&](auto&){++staleChanges;});f.stringValue=@"edited";[f controlTextDidChange:nil];input.setAttribute("type","range");r.sync(host,root.id());[f controlTextDidEndEditing:nil];assert(staleChanges==0&&activeId(d)==-1);input.setAttribute("type","text");r.sync(host,root.id());f=field(host);assert(f);input.focus();invariant(w);const int old=input.id();input.remove();auto replacement=d.createElement("input");assert(replacement.id()==old);replacement.setAttribute("type","text");replacement.style().width(180);replacement.style().height(32);root.appendChild(replacement);r.sync(host,root.id());assert(activeId(d)==-1);input.blur();assert(activeId(d)==-1);replacement.focus();invariant(w);assert(activeId(d)==replacement.id());input.blur();assert(activeId(d)==replacement.id());replacement.blur();r.teardown();t.clear();invariant(w);puts("PASS native owned-window responder focus, typed allocation lifetime and no-front guards; local method scope only");return 0;}}
`
await runNativeTest('native-focus-event-writer-test',{sources:['macos_renderer.mm','canvas_view.mm','press_bridge.mm','image_bridge.mm','color_convert.mm','font_registry.mm','macos_timers.mm','macos_display.mm','macos_sensors.cpp','macos_memory.cpp'],frameworks:['QuartzCore','CoreImage','GameController'],source,args:[]})

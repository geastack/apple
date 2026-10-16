// Authored native control methods against the real renderer and press bridge.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include "macos_background_test.h"
#include "macos_renderer.h"
#include "press_bridge.h"
#include "ui/document.h"
#include "ui/tree_internal.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
namespace gea::macos::thermalright {bool enabled(){return false;}}
@interface InputNeverActiveApplication:NSApplication @end
@implementation InputNeverActiveApplication
-(BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p{if(p!=NSApplicationActivationPolicyProhibited)gea::macos::background_test::refuse("nonprohibited policy");return[super setActivationPolicy:p];}
-(void)activateIgnoringOtherApps:(BOOL)v{(void)v;gea::macos::background_test::refuse("activation");}
-(void)activate{gea::macos::background_test::refuse("activation");}
-(void)unhideWithoutActivation{gea::macos::background_test::refuse("unhide");}
-(void)unhide:(id)v{(void)v;gea::macos::background_test::refuse("unhide");}
@end
@interface InputNeverFrontWindow:NSWindow @end
@implementation InputNeverFrontWindow
-(BOOL)canBecomeKeyWindow{return NO;}-(BOOL)canBecomeMainWindow{return NO;}
-(void)makeKeyWindow{gea::macos::background_test::refuse("make key");}
-(void)makeMainWindow{gea::macos::background_test::refuse("make main");}
-(void)makeKeyAndOrderFront:(id)v{(void)v;gea::macos::background_test::refuse("key/front");}
-(void)orderFront:(id)v{(void)v;gea::macos::background_test::refuse("front");}
-(void)orderFrontRegardless{gea::macos::background_test::refuse("front regardless");}
-(void)orderWindow:(NSWindowOrderingMode)m relativeTo:(NSInteger)n{(void)m;(void)n;gea::macos::background_test::refuse("ordering");}
-(void)orderBack:(id)v{(void)v;gea::macos::background_test::refuse("order back");}
-(void)orderOut:(id)v{(void)v;gea::macos::background_test::refuse("order out");}
@end
static void quiet(NSWindow*w){assert(NSApp&&[NSApp isKindOfClass:InputNeverActiveApplication.class]);assert(NSApp.activationPolicy==NSApplicationActivationPolicyProhibited&&!NSApp.active);assert(!NSApp.keyWindow&&!NSApp.mainWindow);assert(NSApp.windows.count==(w?1:0));for(NSWindow*v in NSApp.windows)assert(v==w&&!v.visible&&!v.keyWindow&&!v.mainWindow);}
static NSView*bound(NSView*view,int node){if(NSNumber*n=objc_getAssociatedObject(view,"gea.node_id");n&&n.intValue==node)return view;for(NSView*child in view.subviews)if(NSView*found=bound(child,node))return found;return nil;}
static NSEvent*down(NSWindow*w){quiet(w);NSEvent*e=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(20,20) modifierFlags:0 timestamp:1 windowNumber:w.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];assert(e.window==w);return e;}
int main(){@autoreleasepool{alarm(12);if(!gea::macos::background_test::enabled()||!getenv("GEA_AUDIO_DISABLED")||strcmp(getenv("GEA_AUDIO_DISABLED"),"1"))gea::macos::background_test::refuse("explicit flags before NSApp");assert(NSApp==nil);auto*app=[InputNeverActiveApplication sharedApplication];if(app.activationPolicy!=NSApplicationActivationPolicyProhibited)[app setActivationPolicy:NSApplicationActivationPolicyProhibited];quiet(nil);
 InputNeverFrontWindow*w=[[InputNeverFrontWindow alloc]initWithContentRect:NSMakeRect(0,0,320,240) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];assert(w.windowNumber>0);quiet(w);
 using namespace gea::embedded::ui;auto&t=Tree::instance();auto&d=Document::instance();t.clear();auto root=d.createElement("div"),button=d.createElement("button");root.style().width(320);root.style().height(240);button.style().width(120);button.style().height(40);root.appendChild(button);d.mount(root,320,240);auto&r=gea::macos::MacosRenderer::instance();r.sync(w.contentView,root.id());quiet(w);
 NSView*oldView=bound(w.contentView,button.id());assert([oldView isKindOfClass:NSButton.class]);PressBridge*oldBridge=objc_getAssociatedObject(oldView,"gea.press_bridge");assert(oldBridge);
 int downs=0,ups=0,cancels=0,clicks=0;button.addEventListener("pointerdown",[&](auto&){++downs;quiet(w);});button.addEventListener("pointerup",[&](auto&){++ups;quiet(w);});button.addEventListener("pointercancel",[&](auto&){++cancels;assert(button.isConnected());quiet(w);});button.addEventListener("click",[&](auto&){++clicks;quiet(w);});
 NSUInteger ticket=[oldBridge beginPointerPress:down(w)];assert(ticket&&downs==1);root.removeChild(button);root.appendChild(button);[oldBridge fire:oldView];[oldBridge endPressTracking:ticket];assert(cancels==1&&ups==0&&clicks==0&&downs==1);quiet(w);
 d.mount(root,320,240);r.sync(w.contentView,root.id());NSView*fresh=bound(w.contentView,button.id());PressBridge*bridge=objc_getAssociatedObject(fresh,"gea.press_bridge");assert(bridge&&fresh!=oldView);ticket=[bridge beginPointerPress:down(w)];assert(ticket);[bridge fire:fresh];[bridge endPressTracking:ticket];assert(downs==2&&ups==1&&clicks==1&&cancels==1);
 auto wrapper=d.createElement("div");root.appendChild(wrapper);wrapper.appendChild(button);d.mount(root,320,240);r.sync(w.contentView,root.id());fresh=bound(w.contentView,button.id());bridge=objc_getAssociatedObject(fresh,"gea.press_bridge");ticket=[bridge beginPointerPress:down(w)];assert(ticket);root.replaceChildren({button});[bridge fire:fresh];[bridge endPressTracking:ticket];assert(downs==3&&ups==2&&clicks==2&&cancels==1);quiet(w);
 r.teardown();t.clear();quiet(w);puts("PASS AppKit binding retirement/retained descendant");}}

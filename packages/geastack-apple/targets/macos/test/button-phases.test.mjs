import { runNativeTest } from './native-harness.mjs'
if (process.platform !== 'darwin') process.exit(0)
await runNativeTest('button-phases-test', {
 sources: ['macos_renderer.mm', 'canvas_view.mm', 'press_bridge.mm', 'image_bridge.mm', 'color_convert.mm', 'font_registry.mm', 'macos_timers.mm', 'macos_display.mm', 'macos_sensors.cpp', 'macos_memory.cpp'],
 frameworks: ['QuartzCore', 'CoreImage'],
 source: String.raw`
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include "ui/tree_internal.h"
#include "ui/node.h"
#include "macos_renderer.h"
#include "press_bridge.h"
#include <cassert>
#include <cstdio>
#include <cmath>
namespace gea::macos::thermalright { bool enabled(){return false;} }

@interface GeaRootClickBridge : NSObject
@property(nonatomic,weak) NSView *rootView;
- (void)fire:(NSGestureRecognizer *)gesture;
@end
@interface AuthoredCancelGesture : NSPressGestureRecognizer
@property(nonatomic) NSGestureRecognizerState authoredState;
@property(nonatomic) NSPoint authoredPoint;
@end
@implementation AuthoredCancelGesture
- (NSGestureRecognizerState)state { return self.authoredState; }
- (NSPoint)locationInView:(NSView *)view { (void)view;return self.authoredPoint; }
@end
static bool checkNativeCancel(NSView *host,NSButton *button,int node) {
 auto &tree=gea::embedded::ui::Tree::instance();int downs=0,ups=0,cancel=0;
 auto down=tree.setEventListener(node,"pointerdown",[&](auto &){++downs;});
 auto up=tree.setEventListener(node,"pointerup",[&](auto &){++ups;});
 auto stopped=tree.setEventListener(node,"pointercancel",[&](auto &e){assert(std::string(e.typeName())=="pointercancel");++cancel;});
 GeaRootClickBridge *bridge=[GeaRootClickBridge new];bridge.rootView=host;
 AuthoredCancelGesture *gesture=[[AuthoredCancelGesture alloc]initWithTarget:nil action:nil];
 gesture.authoredPoint=[button convertPoint:NSMakePoint(button.bounds.size.width/2,button.bounds.size.height/2) toView:host];
 gesture.authoredState=NSGestureRecognizerStateBegan;[bridge fire:gesture];
 gesture.authoredState=NSGestureRecognizerStateCancelled;[bridge fire:gesture];
 std::fprintf(stderr,"native gesture cancellation: downs=%d ups=%d cancel=%d\n",downs,ups,cancel);
 tree.removeEventListener(node,"pointerdown",down);tree.removeEventListener(node,"pointerup",up);tree.removeEventListener(node,"pointercancel",stopped);
 return downs==1&&ups==0&&cancel==1;
}

static int revision=7,starts=0,ends=0,cancels=0,clicks=0,commits=0;
static int captured=0;
static bool mutate=false,activate=true,repeatAction=false,replaceNode=false;
static int originalId=-1,originalRoot=-1,replacementEvents=0;
@interface GeaButton : NSButton
- (void)geaTrackMouseEvent:(NSEvent *)event;
@end
@interface AuthoredGeaButton : GeaButton @end
@implementation AuthoredGeaButton
- (void)geaTrackMouseEvent:(NSEvent *)event {
 [(NSButtonCell *)self.cell trackMouse:event inRect:self.bounds ofView:self untilMouseUp:YES];
}
@end
@interface AuthoredTrackingCell : NSButtonCell @end
@implementation AuthoredTrackingCell
- (BOOL)trackMouse:(NSEvent *)event inRect:(NSRect)rect ofView:(NSView *)view untilMouseUp:(BOOL)until {
 (void)event;(void)rect;(void)until;
 // Authored tracking boundary, not an OS/global-input simulation. The actual
 // NSButton mouseDown and its production target/bridge own both sides.
 assert(starts==1);
 if(mutate)++revision;
 if(replaceNode){auto &tree=gea::embedded::ui::Tree::instance();tree.removeNode(originalId);int next=tree.createButton();assert(next==originalId);tree.setParent(next,originalRoot);tree.node(next).layout.width=120;tree.node(next).layout.height=28;tree.setEventListener(next,"click",[](auto &){++replacementEvents;});}
 NSButton *button=(NSButton *)view;
 if(activate){[(PressBridge *)button.target fire:button];if(repeatAction)[(PressBridge *)button.target fire:button];}
 return activate;
}
@end
@interface NSControl (GeaFixtureCallbacks)
- (void)geaChanged:(id)sender;
- (void)controlTextDidChange:(NSNotification *)note;
@end
static NSControl *findControl(NSView *view,Class type) {
 if([view isKindOfClass:type] && (![view isKindOfClass:[NSTextField class]] || [(NSTextField*)view isEditable]))return (NSControl*)view;
 for(NSView *child in view.subviews)if(auto *found=findControl(child,type))return found;
 return nil;
}
static NSButton *findButton(NSView *view) {
 if([view isKindOfClass:[NSButton class]])return (NSButton *)view;
 for(NSView *child in view.subviews)if(auto *found=findButton(child))return found;
 return nil;
}
static void noActivation(){assert(!NSApp.active&&NSApp.windows.count==0&&NSApp.keyWindow==nil&&NSApp.mainWindow==nil);}
int main(){@autoreleasepool{
 noActivation();using namespace gea::embedded::ui;
 auto &tree=Tree::instance();int root=tree.createView(),buttonId=tree.createButton();tree.setParent(buttonId,root);
 tree.node(root).layout.width=200;tree.node(root).layout.height=100;
 tree.node(buttonId).layout.width=120;tree.node(buttonId).layout.height=28;
 NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,200,100)];
 auto &renderer=gea::macos::MacosRenderer::instance();renderer.sync(host,root);
 NSButton *original=findButton(host);assert(original);
 assert([NSStringFromClass(original.class) isEqualToString:@"GeaButton"]);
 AuthoredGeaButton *button=[[AuthoredGeaButton alloc] initWithFrame:original.frame];
 button.cell=[AuthoredTrackingCell new];button.target=original.target;button.action=original.action;
 assert(button.target==original.target&&button.action==original.action);
 objc_setAssociatedObject(button,"gea.press_bridge",original.target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 objc_setAssociatedObject(button,"gea.node_binding",objc_getAssociatedObject(original,"gea.node_binding"),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 originalId=buttonId;originalRoot=root;
 tree.setEventListener(buttonId,"pointerdown",[](auto &){++starts;captured=revision;});
 tree.setEventListener(buttonId,"pointerup",[](auto &){++ends;});
 tree.setEventListener(buttonId,"pointercancel",[](auto &e){assert(std::string(e.typeName())=="pointercancel");++cancels;captured=-1;});
 tree.setEventListener(buttonId,"click",[](auto &){++clicks;if(captured==revision)++commits;});
 NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(2,2) modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
 mutate=true;[button mouseDown:down];
 std::fprintf(stderr,"mutated revision: starts=%d ends=%d clicks=%d commits=%d cancels=%d\n",starts,ends,clicks,commits,cancels);
 assert(starts==1&&ends==1&&clicks==1&&commits==0&&cancels==0);
 starts=ends=clicks=cancels=commits=0;mutate=false;activate=false;[button mouseDown:down];
 assert(starts==1&&ends==0&&clicks==0&&cancels==1);
 starts=ends=clicks=cancels=commits=0;activate=true;repeatAction=true;[button mouseDown:down];
 assert(starts==1&&ends==1&&clicks==1&&commits==1);
 starts=ends=clicks=cancels=commits=0;repeatAction=false;
 [(PressBridge *)button.target fire:button];
 assert(starts==0&&ends==0&&clicks==1);
 // Native focused button keys activate on keyUp without pointer phases, as in
 // a browser, suppress repeat/echo and let application prevention own activation.
 auto key=[](NSEventType type,bool repeat){return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:repeat keyCode:49];};
 starts=ends=clicks=cancels=commits=0;
 [button keyDown:key(NSEventTypeKeyDown,false)];assert(starts==0&&clicks==0);
 [button keyUp:key(NSEventTypeKeyUp,false)];assert(starts==0&&ends==0&&clicks==1);
 starts=ends=clicks=cancels=commits=0;
 [button keyDown:key(NSEventTypeKeyDown,false)];[button keyDown:key(NSEventTypeKeyDown,true)];
 [button keyUp:key(NSEventTypeKeyUp,false)];[button keyUp:key(NSEventTypeKeyUp,false)];assert(starts==0&&ends==0&&clicks==1);
 starts=ends=clicks=cancels=commits=0;
 [button keyDown:key(NSEventTypeKeyDown,false)];[button cancelOperation:nil];
 [button keyUp:key(NSEventTypeKeyUp,false)];assert(starts==0&&cancels==1&&ends==0&&clicks==0);
 const auto prevent=tree.setEventListener(buttonId,"keydown",[](auto &e){assert(e.code=="Space");e.preventDefault();});
 starts=ends=clicks=cancels=commits=0;
 [button keyDown:key(NSEventTypeKeyDown,false)];[button keyUp:key(NSEventTypeKeyUp,false)];assert(starts==0&&clicks==0);
 assert(tree.removeEventListener(buttonId,"keydown",prevent));
 starts=ends=clicks=cancels=commits=0;replaceNode=true;[button mouseDown:down];
 assert(starts==1&&ends==0&&clicks==0&&replacementEvents==0);
 [(PressBridge *)button.target fire:button];assert(replacementEvents==0);
 renderer.sync(host,root);assert(findButton(host)&&findButton(host)!=original); // new birth gets a new view
 [(PressBridge *)button.target fire:button];assert(replacementEvents==0);
 assert(checkNativeCancel(host,findButton(host),buttonId));
 renderer.teardown();tree.clear();
 // Old native value controls must not target the same integer's next birth,
 // before OR after renderer sync. Live replacements must still work.
 for(bool text:{false,true}) {
  int r=tree.createView(),id=tree.createView();tree.setParent(id,r);NodeHandle(id).setTagName("input");
  tree.setAttribute(id,"type",text?"text":"range");tree.setAttribute(id,"min","-1");tree.setAttribute(id,"max","1");tree.setAttribute(id,"step","0.01");tree.setAttribute(id,"value",text?"initial":"0.11");
  tree.node(r).layout.width=200;tree.node(r).layout.height=100;tree.node(id).layout.width=150;tree.node(id).layout.height=28;
  renderer.sync(host,r);NSControl *old=findControl(host,text?[NSTextField class]:[NSSlider class]);assert(old);
  tree.removeNode(id);int next=tree.createView();assert(next==id);tree.setParent(next,r);NodeHandle(next).setTagName("input");
  tree.setAttribute(next,"type",text?"text":"range");tree.setAttribute(next,"min","-1");tree.setAttribute(next,"max","1");tree.setAttribute(next,"step","0.01");tree.setAttribute(next,"value",text?"fresh":"0.77");
  tree.node(next).layout.width=150;tree.node(next).layout.height=28;
  int inputEvents=0;tree.setEventListener(next,"input",[&](auto &){++inputEvents;});
  auto changed=[&](NSControl *control,bool live){
   if(text){control.stringValue=live?@"typed":@"stale";[control controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:control]];}
   else {control.doubleValue=live?0.55:0.33;[control geaChanged:control];}
  };
  changed(old,false);assert(inputEvents==0&&std::string(tree.getAttribute(next,"value"))==(text?"fresh":"0.77"));
  renderer.sync(host,r);NSControl *current=findControl(host,text?[NSTextField class]:[NSSlider class]);assert(current&&current!=old);
  changed(old,false);assert(inputEvents==0);changed(current,true);assert(inputEvents==1);
  assert(text?std::string(tree.getAttribute(next,"value"))=="typed":std::abs(std::stod(tree.getAttribute(next,"value"))-0.55)<1e-10);
  renderer.teardown();inputEvents=0;changed(current,false);assert(inputEvents==0);
  assert(text?std::string(tree.getAttribute(next,"value"))=="typed":std::abs(std::stod(tree.getAttribute(next,"value"))-0.55)<1e-10);
  tree.clear();
 }
 noActivation();
 std::puts("PASS native button phase/stale/cancel/repeat/programmatic and stale slider/input predicates; authored tracking, no activation/global input/audio.");
}}
`,
})

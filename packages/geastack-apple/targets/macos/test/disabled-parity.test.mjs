import {runNativeTest} from './native-harness.mjs'
if(process.platform!=='darwin')process.exit(0)
await runNativeTest('disabled-parity-test',{
 sources:['macos_renderer.mm','canvas_view.mm','press_bridge.mm','image_bridge.mm','color_convert.mm','font_registry.mm','macos_timers.mm','macos_display.mm','macos_sensors.cpp','macos_memory.cpp'],
 frameworks:['QuartzCore','CoreImage'],
 // Hidden-window test mode: no activation, no visible window, no audio.
 env:{GEA_MACOS_BACKGROUND_TEST:'1',GEA_AUDIO_DISABLED:'1'},
 source:String.raw`
#import <AppKit/AppKit.h>
#include "ui/tree_internal.h"
#include "ui/node.h"
#include "macos_renderer.h"
#include "press_bridge.h"
#include "macos_background_test.h"
#include <unistd.h>
#import <objc/runtime.h>
#include <cassert>
#include <cstdio>
namespace gea::macos::thermalright {bool enabled(){return false;}}
@interface NSControl(DisabledParityAction)
-(void)geaChanged:(id)sender;
-(void)controlTextDidChange:(NSNotification*)note;
-(void)controlTextDidEndEditing:(NSNotification*)note;
@end
@interface NSTextView(DisabledParityChange)
-(void)textDidChange:(NSNotification*)note;
-(void)textDidEndEditing:(NSNotification*)note;
@end
static NSControl*find(NSView*v,Class c){if([v isKindOfClass:c])return (NSControl*)v;for(NSView*k in v.subviews)if(auto*r=find(k,c))return r;return nil;}
static NSView*findAny(NSView*v,Class c){if([v isKindOfClass:c])return v;for(NSView*k in v.subviews)if(auto*r=findAny(k,c))return r;return nil;}
@interface DisabledNeverActiveApplication:NSApplication @end
@implementation DisabledNeverActiveApplication
-(BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p {if(p!=NSApplicationActivationPolicyProhibited)gea::macos::background_test::refuse("nonprohibited policy");return [super setActivationPolicy:p];}
-(void)activateIgnoringOtherApps:(BOOL)b {(void)b;gea::macos::background_test::refuse("activation refused");}
-(void)activate {gea::macos::background_test::refuse("activation refused");}
-(void)unhide:(id)sender {(void)sender;gea::macos::background_test::refuse("unhide refused");}
-(void)unhideWithoutActivation {gea::macos::background_test::refuse("unhide refused");}
@end
static unsigned quietStage=0;
static void quiet(){fprintf(stderr,"quiet stage=%u policy=%ld active=%d windows=%lu key=%p main=%p\n",++quietStage,(long)NSApp.activationPolicy,(int)NSApp.active,(unsigned long)NSApp.windows.count,(__bridge void*)NSApp.keyWindow,(__bridge void*)NSApp.mainWindow);for(NSWindow*w in NSApp.windows)fprintf(stderr,"owned window class=%s visible=%d key=%d main=%d\n",NSStringFromClass(w.class).UTF8String,(int)w.visible,(int)w.keyWindow,(int)w.mainWindow);assert(NSApp.activationPolicy==NSApplicationActivationPolicyProhibited&&!NSApp.active&&NSApp.keyWindow==nil&&NSApp.mainWindow==nil);
 assert(NSApp.windows.count<=1);
 for(NSWindow*w in NSApp.windows)assert([NSStringFromClass(w.class)isEqualToString:@"TUINSWindow"]&&!w.visible&&!w.keyWindow&&!w.mainWindow);}

int main(){@autoreleasepool{
 alarm(12);if(!gea::macos::background_test::enabled())gea::macos::background_test::refuse("explicit background mode required");const char*audio=getenv("GEA_AUDIO_DISABLED");if(!audio||strcmp(audio,"1"))gea::macos::background_test::refuse("audio fence required");
 assert(NSApp==nil);NSApplication*app=[DisabledNeverActiveApplication sharedApplication];assert([app isKindOfClass:DisabledNeverActiveApplication.class]);if(app.activationPolicy!=NSApplicationActivationPolicyProhibited)[app setActivationPolicy:NSApplicationActivationPolicyProhibited];gea::macos::background_test::checkApplication(app);quiet();using namespace gea::embedded::ui;auto&t=Tree::instance();int root=t.createView(),r=t.createView();NodeHandle range(r);range.setTagName("input");range.setAttribute("type","range");range.setAttribute("min","-120");range.setAttribute("max","12");range.setAttribute("step","0.5");range.setAttribute("value","0");t.setParent(r,root);t.node(root).layout.width=200;t.node(root).layout.height=100;t.node(r).layout.width=180;t.node(r).layout.height=28;
 NSView*host=[[NSView alloc]initWithFrame:NSMakeRect(0,0,200,100)];auto&renderer=gea::macos::MacosRenderer::instance();int inputs=0,rangeChanges=0;t.setEventListener(r,"input",[&](auto&){++inputs;});t.setEventListener(r,"change",[&](auto&e){assert(!strcmp(e.typeName(),"change")&&!e.cancelable);++rangeChanges;});
 auto sync=[&]{renderer.sync(host,root);auto*s=(NSSlider*)find(host,NSSlider.class);assert(s);quiet();return s;};
 auto*s=sync();assert(s.enabled&&range.matches(":enabled"));
 range.setAttribute("disabled","false");s=sync();assert(range.matches(":disabled")&&!s.enabled);s.doubleValue=-54.5;[s geaChanged:s];assert(inputs==0&&rangeChanges==0&&std::string(range.getAttribute("value"))=="0");
 range.setDisabled(false);s=sync();assert(s.enabled&&range.matches(":enabled"));s.doubleValue=-54.5;[s geaChanged:s];assert(inputs==1&&rangeChanges==1&&std::stod(range.getAttribute("value"))==-54.5);[s geaChanged:s];assert(inputs==2&&rangeChanges==1);
 range.setDisabled(true);s=sync();assert(!s.enabled&&range.matches(":disabled"));[s geaChanged:s];assert(inputs==2&&rangeChanges==1);
 renderer.teardown();t.clear();quiet();
 // Every actual writer is exercised with live disabled state changed AFTER
 // materialization: cached NSControl.enabled must not authorize mutation.
 for(const char*kind:{"text","checkbox","radio","select","stepper","textarea"}) {
  fprintf(stderr,"materialize control=%s\n",kind);int owner=t.createView(),node=t.createView();NodeHandle n(node);const bool area=std::string(kind)=="textarea";
  n.setTagName(area?"textarea":std::string(kind)=="select"?"select":std::string(kind)=="stepper"?"stepper":"input");
  if(std::string(kind)=="text"||std::string(kind)=="checkbox"||std::string(kind)=="radio")n.setAttribute("type",kind);
  n.setAttribute("value","0");n.setAttribute("checked","false");t.setParent(node,owner);t.node(owner).layout.width=200;t.node(owner).layout.height=100;t.node(node).layout.width=180;t.node(node).layout.height=40;
  if(std::string(kind)=="select"){int option=t.createView();NodeHandle(option).setTagName("option");t.setAttribute(option,"value","new");t.setParent(option,node);}
  NSView*container=[[NSView alloc]initWithFrame:NSMakeRect(0,0,200,100)];int count=0,commits=0;t.setEventListener(node,"input",[&](auto&){++count;});t.setEventListener(node,"change",[&](auto&){++commits;});renderer.sync(container,owner);
  NSControl*c=find(container,NSControl.class);NSTextView*tv=nil;if(area){tv=(NSTextView*)findAny(container,NSTextView.class);assert(tv);}else assert(c);
  auto action=[&]{if(area){tv.string=@"changed";[tv textDidChange:nil];}else if([c isKindOfClass:NSTextField.class]){((NSTextField*)c).stringValue=@"changed";[c controlTextDidChange:nil];}else{if([c respondsToSelector:@selector(setState:)])[(id)c setState:NSControlStateValueOn];if([c isKindOfClass:NSStepper.class])((NSStepper*)c).doubleValue=1;[c geaChanged:c];}};
  n.setDisabled(true);action();assert(count==0&&commits==0&&std::string(n.getAttribute("value"))=="0"&&std::string(n.getAttribute("checked"))=="false");renderer.sync(container,owner);if(area)assert(!tv.editable);else assert(!c.enabled);
  n.setDisabled(false);renderer.sync(container,owner);action();assert(count==1);if(area){assert(commits==0);[tv textDidEndEditing:nil];[tv textDidEndEditing:nil];}else if([c isKindOfClass:NSTextField.class]){assert(commits==0);[c controlTextDidEndEditing:nil];[c controlTextDidEndEditing:nil];}assert(commits==1);quiet();renderer.teardown();t.clear();
 }
 // Held pointer and keyboard activation must cancel, never release/click,
 // when canonical disabled state changes before the cached view refreshes.
 for(bool keyboard:{false,true}) {
  int owner=t.createView(),node=t.createButton();NodeHandle n(node);t.setParent(node,owner);t.node(owner).layout.width=200;t.node(owner).layout.height=100;t.node(node).layout.width=160;t.node(node).layout.height=40;
  NSView*container=[[NSView alloc]initWithFrame:NSMakeRect(0,0,200,100)];renderer.sync(container,owner);NSButton*b=(NSButton*)find(container,NSButton.class);assert(b);PressBridge*bridge=objc_getAssociatedObject(b,"gea.press_bridge");assert(bridge);
  int downs=0,ups=0,clicks=0,cancels=0,keys=0;t.setEventListener(node,"keydown",[&](auto&e){++keys;assert(e.button==-1&&e.buttons==0);});t.setEventListener(node,"pointerdown",[&](auto&e){++downs;assert(e.button==0&&e.buttons==1);});t.setEventListener(node,"pointerup",[&](auto&){++ups;});t.setEventListener(node,"click",[&](auto&){++clicks;});t.setEventListener(node,"pointercancel",[&](auto&){++cancels;});
  NSEvent*down=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
  NSEvent*up=[NSEvent keyEventWithType:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
  NSEvent*mouse=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(20,20) modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
  NSUInteger ticket=0;if(keyboard)[b keyDown:down];else ticket=[bridge beginPointerPress:mouse];assert(downs==(keyboard?0:1)&&keys==(keyboard?1:0));
  n.setDisabled(true);if(keyboard)[b keyUp:up];else{[bridge fire:b];[bridge endPressTracking:ticket];}fprintf(stderr,"held outcome keyboard=%d downs=%d ups=%d clicks=%d cancels=%d disabled=%d ownerValid=%d\n",(int)keyboard,downs,ups,clicks,cancels,(int)n.disabled(),(int)n.valid());assert(ups==0&&clicks==0&&cancels==1);
  [bridge fire:b];assert(downs==(keyboard?0:1)&&clicks==0);
  // A fresh enabled gesture activates once; keyboard carries no pointer phases.
  n.setDisabled(false);if(keyboard){[b keyDown:down];[b keyUp:up];}else{ticket=[bridge beginPointerPress:mouse];[bridge fire:b];[bridge fire:b];[bridge endPressTracking:ticket];}
  assert(clicks==1&&ups==(keyboard?0:1)&&downs==(keyboard?0:2));
  // Explicit programmatic activation is a separate atomic Click, not a left edge.
  int atomic=0;auto atomicListener=t.setEventListener(node,"click",[&](auto&e){assert(e.button==-1&&e.buttons==0);++atomic;});
  gea_macos_fire_press_for_node(node);assert(atomic==1&&clicks==2&&downs==(keyboard?0:2));t.removeEventListener(node,"click",atomicListener);quiet();renderer.teardown();t.clear();
 }
 // Left/right native event kinds identify the changed edge. The factory
 // cannot author a numbered Other button: its zero metadata must be refused.
 for(auto pair:{std::pair<NSEventType,int>{NSEventTypeLeftMouseDown,0},{NSEventTypeRightMouseDown,2},{NSEventTypeOtherMouseDown,1}}){
  int node=t.createButton();PressBridge*bridge=[PressBridge new];bridge.nodeId=node;
  NSEvent*event=[NSEvent mouseEventWithType:pair.first location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
  fprintf(stderr,"native button mapping eventtype=%lu buttonNumber=%ld expectedDOM=%d\n",(unsigned long)event.type,(long)event.buttonNumber,pair.second);
  int observed=0;t.setEventListener(node,"pointerdown",[&](auto&e){assert(e.button==pair.second&&e.buttons==(pair.second==2?2u:1u));++observed;});
  const auto ticket=[bridge beginPointerPress:event];if(pair.first==NSEventTypeOtherMouseDown){assert(event.buttonNumber<2&&ticket==0&&observed==0);}else{assert(ticket&&observed==1);}[bridge cancelPress:nil];[bridge endPressTracking:ticket];t.clear();
 }
 quiet();puts("native disabled projection and input refusal passed; only the hidden AppKit text-input service window exists");return 0;
}}
`})

// Drives the production root bridge methods with authored recognizer
// phase/location input; no physical recognition or tracking.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include "macos_background_test.h"
#include "macos_renderer.h"
#include "ui/document.h"
#include "ui/tree_internal.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <cmath>
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

@interface NSObject (RootBridgeFixtureDeclaration)
-(void)fire:(NSGestureRecognizer*)recognizer;
-(id)pressedBinding;
-(BOOL)ending;
@end
// Only input state is authored. All hit testing, binding/identity, event dispatch,
// cancellation and terminal cleanup are the actual installed bridge's methods.
@interface LocalRootPhase:NSGestureRecognizer
@property(nonatomic)NSGestureRecognizerState authoredState;
@property(nonatomic)NSPoint authoredLocation;
@end
@implementation LocalRootPhase
-(NSGestureRecognizerState)state{return self.authoredState;}
-(NSPoint)locationInView:(NSView*)view{assert(view==self.view);return self.authoredLocation;}
@end
static void phase(id bridge,LocalRootPhase*input,NSGestureRecognizerState state,NSWindow*w,int x=20,int y=20){quiet(w);input.authoredState=state;input.authoredLocation=NSMakePoint(x,input.view.bounds.size.height-y);[bridge fire:input];quiet(w);}
static void rootDiagnostic(const char*stage,id captured,LocalRootPhase*input,NSWindow*w,gea::embedded::ui::NodeHandle target,int downs,int ups,int clicks,int cancels){
 quiet(w);id current=objc_getAssociatedObject(w.contentView,"gea.root_click_bridge");assert(current&&[current isKindOfClass:NSClassFromString(@"GeaRootClickBridge")]);bool installed=false;for(NSGestureRecognizer*gr in w.contentView.gestureRecognizers)if([gr isKindOfClass:NSPressGestureRecognizer.class]&&gr.target==current)installed=true;assert(installed);
 auto&t=gea::embedded::ui::Tree::instance();const auto box=t.node(target.id()).layout;NSPoint p=NSMakePoint(20,input.view.bounds.size.height-20);NSView*hit=[input.view hitTest:[input.view convertPoint:p toView:input.view.superview]];NSNumber*hitId=nil;for(NSView*v=hit;v&&!hitId;v=v.superview)hitId=objc_getAssociatedObject(v,"gea.node_id");
 NSView*targetView=nil;NSMutableArray<NSView*>*todo=[NSMutableArray arrayWithObject:w.contentView];while(todo.count){NSView*v=todo.lastObject;[todo removeLastObject];NSNumber*n=objc_getAssociatedObject(v,"gea.node_id");if(n&&n.intValue==target.id()){targetView=v;break;}[todo addObjectsFromArray:v.subviews];}
 assert(targetView);NSRect native=[targetView convertRect:targetView.bounds toView:w.contentView];std::fprintf(stderr,"ROOT_DIAG %s captured=%p current=%p same=%d target=%d tree=%d,%d,%d,%d native=%.1f,%.1f,%.1f,%.1f fixedHit=%d counters=%d,%d,%d,%d\n",stage,(__bridge void*)captured,(__bridge void*)current,captured==current,target.id(),box.x,box.y,box.width,box.height,native.origin.x,native.origin.y,native.size.width,native.size.height,hitId?hitId.intValue:-1,downs,ups,clicks,cancels);std::fflush(stderr);
}
namespace gea::macos {int nodeIdForView(NSView*view);}
static void freshPhase(id bridge,LocalRootPhase*input,NSGestureRecognizerState state,NSWindow*w,gea::embedded::ui::NodeHandle target){
 quiet(w);assert(target.valid()&&target.isConnected());assert(bridge==objc_getAssociatedObject(w.contentView,"gea.root_click_bridge"));auto&t=gea::embedded::ui::Tree::instance();const auto box=t.node(target.id()).layout;assert(box.width>0&&box.height>0);
 NSView*targetView=nil;NSMutableArray<NSView*>*todo=[NSMutableArray arrayWithObject:w.contentView];while(todo.count){NSView*v=todo.lastObject;[todo removeLastObject];NSNumber*n=objc_getAssociatedObject(v,"gea.node_id");if(n&&n.intValue==target.id()&&gea::macos::nodeIdForView(v)==target.id()){targetView=v;break;}[todo addObjectsFromArray:v.subviews];}
 assert(targetView&&targetView.window==w);const NSRect native=[targetView convertRect:targetView.bounds toView:input.view];assert(std::abs(native.origin.x-box.x)<0.5&&std::abs(input.view.bounds.size.height-NSMaxY(native)-box.y)<0.5&&std::abs(native.size.width-box.width)<0.5&&std::abs(native.size.height-box.height)<0.5);
 const int x=box.x+box.width/2,y=box.y+box.height/2;const NSPoint p=NSMakePoint(x,input.view.bounds.size.height-y);NSView*hit=[input.view hitTest:[input.view convertPoint:p toView:input.view.superview]];assert(gea::macos::nodeIdForView(hit)==target.id());std::fprintf(stderr,"ROOT_FRESH target=%d canonical=%d,%d hit=%d\n",target.id(),x,y,gea::macos::nodeIdForView(hit));std::fflush(stderr);phase(bridge,input,state,w,x,y);
}
int main(){@autoreleasepool{alarm(12);if(!gea::macos::background_test::enabled()||!getenv("GEA_AUDIO_DISABLED")||strcmp(getenv("GEA_AUDIO_DISABLED"),"1"))gea::macos::background_test::refuse("explicit flags before NSApp");assert(NSApp==nil);auto*app=[InputNeverActiveApplication sharedApplication];if(app.activationPolicy!=NSApplicationActivationPolicyProhibited)[app setActivationPolicy:NSApplicationActivationPolicyProhibited];quiet(nil);
 InputNeverFrontWindow*w=[[InputNeverFrontWindow alloc]initWithContentRect:NSMakeRect(0,0,320,240) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];assert(w.windowNumber>0);quiet(w);
 using namespace gea::embedded::ui;auto&t=Tree::instance();auto&d=Document::instance();auto&r=gea::macos::MacosRenderer::instance();
 for(const char*name:{"detach","retained","unrelated","cancel-throw","cancel-reentry","up-reentry","up-throw","up-reentry-throw"}){
  const std::string mode=name;r.teardown();t.clear();auto root=d.createElement("div"),target=d.createElement("div"),other=d.createElement("div"),wrapper=d.createElement("div");root.style().width(320);root.style().height(240);target.style().width(120);target.style().height(40);other.style().width(120);other.style().height(40);wrapper.style().width(120);wrapper.style().height(40);root.appendChild(wrapper);wrapper.appendChild(target);root.appendChild(other);d.mount(root,320,240);r.sync(w.contentView,root.id());quiet(w);
  id bridge=objc_getAssociatedObject(w.contentView,"gea.root_click_bridge");assert(bridge&&[bridge isKindOfClass:NSClassFromString(@"GeaRootClickBridge")]);bool installed=false;for(NSGestureRecognizer*gr in w.contentView.gestureRecognizers)if([gr isKindOfClass:NSPressGestureRecognizer.class]&&gr.target==bridge)installed=true;assert(installed);
  LocalRootPhase*input=[[LocalRootPhase alloc]initWithTarget:nil action:nil];[w.contentView addGestureRecognizer:input];
  int downs=0,ups=0,moves=0,cancels=0,clicks=0;bool reentered=false;target.addEventListener("pointerdown",[&](auto&e){++downs;assert(e.targetId==target.id());quiet(w);});target.addEventListener("pointermove",[&](auto&){++moves;quiet(w);});target.addEventListener("click",[&](auto&){++clicks;quiet(w);});
  target.addEventListener("pointerup",[&](auto&){++ups;quiet(w);if((mode=="up-reentry"||mode=="up-reentry-throw")&&!reentered){reentered=true;phase(bridge,input,NSGestureRecognizerStateBegan,w);if(mode=="up-reentry-throw")throw std::runtime_error("authored reentrant root up");}if(mode=="up-throw"&&!reentered){reentered=true;throw std::runtime_error("authored root up");}});
  target.addEventListener("pointercancel",[&](auto&e){++cancels;assert(target.isConnected()&&e.clientX==20&&e.clientY==20);quiet(w);if(mode=="cancel-throw")throw std::runtime_error("authored root cancel");if(mode=="cancel-reentry"&&!reentered){reentered=true;d.refresh(root,320,240);r.sync(w.contentView,root.id());rootDiagnostic(mode.c_str(),bridge,input,w,target,downs,ups,clicks,cancels);freshPhase(bridge,input,NSGestureRecognizerStateBegan,w,target);}});
  phase(bridge,input,NSGestureRecognizerStateBegan,w);assert(downs==1);
  if(mode=="detach"){
   root.removeChild(wrapper);root.appendChild(wrapper);phase(bridge,input,NSGestureRecognizerStateChanged,w,21);phase(bridge,input,NSGestureRecognizerStateEnded,w,21);assert(cancels==1&&ups==0&&clicks==0&&moves==0);d.refresh(root,320,240);r.sync(w.contentView,root.id());rootDiagnostic(mode.c_str(),bridge,input,w,target,downs,ups,clicks,cancels);freshPhase(bridge,input,NSGestureRecognizerStateBegan,w,target);freshPhase(bridge,input,NSGestureRecognizerStateEnded,w,target);rootDiagnostic("fresh-result",bridge,input,w,target,downs,ups,clicks,cancels);assert(downs==2&&ups==1&&clicks==1&&cancels==1);
  }else if(mode=="retained"||mode=="unrelated"){
   if(mode=="retained")root.replaceChildren({target,other});else root.removeChild(other);phase(bridge,input,NSGestureRecognizerStateEnded,w);assert(downs==1&&ups==1&&clicks==1&&cancels==0);
  }else if(mode=="cancel-throw"||mode=="cancel-reentry"){
   bool refused=false;try{root.removeChild(wrapper);}catch(const std::runtime_error&){refused=true;}assert(refused&&wrapper.isConnected()&&target.isConnected()&&cancels==1);
   if(mode=="cancel-throw"){phase(bridge,input,NSGestureRecognizerStateChanged,w,21);phase(bridge,input,NSGestureRecognizerStateEnded,w,21);assert(ups==0&&clicks==0&&moves==0);d.refresh(root,320,240);r.sync(w.contentView,root.id());rootDiagnostic(mode.c_str(),bridge,input,w,target,downs,ups,clicks,cancels);freshPhase(bridge,input,NSGestureRecognizerStateBegan,w,target);}
   assert(downs==2);phase(bridge,input,NSGestureRecognizerStateEnded,w);assert(ups==1&&clicks==1&&cancels==1);
  }else if(mode=="up-reentry"||mode=="up-reentry-throw"){
   if(mode=="up-reentry-throw"){bool threw=false;try{phase(bridge,input,NSGestureRecognizerStateEnded,w);}catch(const std::runtime_error&){threw=true;}assert(threw&&[bridge pressedBinding]!=nil&&![bridge ending]);}else phase(bridge,input,NSGestureRecognizerStateEnded,w);assert(downs==2&&ups==1&&clicks==0);phase(bridge,input,NSGestureRecognizerStateEnded,w);assert(ups==2&&clicks==1&&cancels==0);if(mode=="up-reentry-throw")assert([bridge pressedBinding]==nil&&![bridge ending]);
  }else{
   bool threw=false;try{phase(bridge,input,NSGestureRecognizerStateEnded,w);}catch(const std::runtime_error&){threw=true;}assert(threw&&ups==1&&clicks==0);std::fprintf(stderr,"ROOT_UP_THROW binding=%p ending=%d\n",(__bridge void*)[bridge pressedBinding],[bridge ending]);std::fflush(stderr);assert([bridge pressedBinding]==nil&&![bridge ending]);root.removeChild(wrapper);root.appendChild(wrapper);phase(bridge,input,NSGestureRecognizerStateEnded,w);assert(cancels==0&&ups==1&&clicks==0);d.refresh(root,320,240);r.sync(w.contentView,root.id());rootDiagnostic(mode.c_str(),bridge,input,w,target,downs,ups,clicks,cancels);freshPhase(bridge,input,NSGestureRecognizerStateBegan,w,target);freshPhase(bridge,input,NSGestureRecognizerStateEnded,w,target);assert(downs==2&&ups==2&&clicks==1);
  }
  [w.contentView removeGestureRecognizer:input];quiet(w);std::printf("PASS root bridge %s\n",name);
 }
 r.teardown();t.clear();quiet(w);puts("PASS root bridge retirement/reentry/exception methods");}}

// Renderer projection only: real Tree -> detached NSView hierarchy. No window,
// input, AppKit run loop, activation or audio.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include "macos_background_test.h"
#include "macos_renderer.h"
#include "ui/document.h"
#include "ui/tree_internal.h"
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <unistd.h>
namespace gea::macos::thermalright {bool enabled(){return false;}}
@interface StructuralNeverActiveApplication:NSApplication @end
@implementation StructuralNeverActiveApplication
-(BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p{if(p!=NSApplicationActivationPolicyProhibited)gea::macos::background_test::refuse("nonprohibited policy");return[super setActivationPolicy:p];}
-(void)activateIgnoringOtherApps:(BOOL)flag{(void)flag;gea::macos::background_test::refuse("activation");}
-(void)activate{gea::macos::background_test::refuse("activation");}
-(void)unhideWithoutActivation{gea::macos::background_test::refuse("unhide");}
-(void)unhide:(id)sender{(void)sender;gea::macos::background_test::refuse("unhide");}
@end
static void quiet(){assert(NSApp&&[NSApp isKindOfClass:StructuralNeverActiveApplication.class]);assert(NSApp.activationPolicy==NSApplicationActivationPolicyProhibited&&!NSApp.active);assert(NSApp.windows.count==0&&!NSApp.keyWindow&&!NSApp.mainWindow);}
static void collect(NSView*view,std::vector<int>&ids){if(NSNumber*value=objc_getAssociatedObject(view,"gea.node_id"))ids.push_back(value.intValue);for(NSView*child in view.subviews)collect(child,ids);}
static std::vector<int> bindings(NSView*host){quiet();std::vector<int>ids;collect(host,ids);std::sort(ids.begin(),ids.end());return ids;}
static bool has(const std::vector<int>&ids,int value){return std::find(ids.begin(),ids.end(),value)!=ids.end();}
int main(){@autoreleasepool{alarm(12);if(!gea::macos::background_test::enabled()||!getenv("GEA_AUDIO_DISABLED")||strcmp(getenv("GEA_AUDIO_DISABLED"),"1"))gea::macos::background_test::refuse("explicit background/audio flags before NSApp");assert(NSApp==nil);auto*app=[StructuralNeverActiveApplication sharedApplication];assert([app isKindOfClass:StructuralNeverActiveApplication.class]);if(app.activationPolicy!=NSApplicationActivationPolicyProhibited)[app setActivationPolicy:NSApplicationActivationPolicyProhibited];quiet();
 using namespace gea::embedded::ui;auto&t=Tree::instance();auto&d=Document::instance();t.clear();auto root=d.createElement("div"),element=d.createElement("div"),comment=d.createComment("must not create an NSView");root.style().width(300);root.style().height(200);root.style().setProperty("display","flex");element.style().width(20);element.style().height(20);comment.style().width(100);comment.style().height(100);comment.style().setProperty("background-color","red");root.appendChild(element);root.appendChild(comment);d.mount(root,300,200);
 NSView*host=[[NSView alloc]initWithFrame:NSMakeRect(0,0,300,200)];assert(host.window==nil);auto&r=gea::macos::MacosRenderer::instance();r.sync(host,root.id());auto ids=bindings(host);fprintf(stderr,"structural native bindings=%zu commentPresent=%d\n",ids.size(),has(ids,comment.id()));assert(has(ids,root.id())&&has(ids,element.id()));assert(!has(ids,comment.id())&&ids.size()==2);
 auto fragment=d.createDocumentFragment(),moved=d.createElement("div");moved.style().width(20);moved.style().height(20);fragment.appendChild(moved);fragment.style().width(100);fragment.style().height(100);fragment.style().setProperty("background-color","blue");r.sync(host,fragment.id());ids=bindings(host);assert(ids.empty());assert(!has(ids,fragment.id())&&!has(ids,moved.id()));root.appendChild(fragment);d.mount(root,300,200);r.sync(host,root.id());ids=bindings(host);assert(ids.size()==3&&has(ids,moved.id())&&!has(ids,fragment.id())&&!has(ids,comment.id()));assert(!fragment.firstChildHandle().valid());
 int slot=element.id();element.remove();auto recycled=d.createComment("same slot structural replacement");assert(recycled.id()==slot);root.appendChild(recycled);d.mount(root,300,200);r.sync(host,root.id());ids=bindings(host);assert(ids.size()==2&&has(ids,root.id())&&has(ids,moved.id())&&!has(ids,slot));r.teardown();assert(bindings(host).empty());t.clear();quiet();puts("PASS AppKit structural comments/fragments have no native view; transfer and retired-slot sweep");}}

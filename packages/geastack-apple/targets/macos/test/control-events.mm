#import <AppKit/AppKit.h>
#include "ui/tree_internal.h"
#include "ui/node.h"
#include "../main/macos_renderer.h"
#include <cassert>
#include <string>
#include <cstdio>
int main(){
 @autoreleasepool {
  using namespace gea::embedded::ui;
  auto &tree=Tree::instance();
  const int root=tree.createView();
  tree.setAttribute(root,"data-gea-inputs","true");
  NodeHandle projected=gea::framework::events::EventTarget(root);
  assert(projected.id()==root);
  projected=gea::framework::events::EventTarget(root);
  assert(std::string(projected.getAttribute("data-gea-inputs"))=="true");
  int key=0;
  setDocumentEventListener("keydown",[&](auto &event){key=event.keyCode;});
  GeaContentView *view=[[GeaContentView alloc] initWithFrame:NSZeroRect];
  assert(view.acceptsFirstResponder);
  assert(![view isKindOfClass:[NSControl class]]);
  [view geaSendKey:39];assert(key==39);
  std::string committed;
  tree.setEventListener(root,"input",[&](auto &event){committed=tree.getAttribute(event.currentTargetId,"value");});
  [view insertText:@"Mira ü" replacementRange:NSMakeRange(NSNotFound,0)];
  assert(committed=="Mira ü");
  const int control=tree.createView(),child=tree.createText();
  tree.setParent(control,root);tree.setParent(child,control);
  tree.setAttribute(control,"data-gea-control","true");
  tree.node(control).layout.x=510;tree.node(control).layout.y=120;
  tree.node(control).layout.width=180;tree.node(control).layout.height=28;
  gea::macos::publishControlEventBounds(child);
  assert(std::stof(tree.getAttribute(control,"data-gea-x"))==510);
  assert(std::stof(tree.getAttribute(control,"data-gea-y"))==120);
  assert(std::stof(tree.getAttribute(control,"data-gea-width"))==180);
  assert(std::stof(tree.getAttribute(control,"data-gea-height"))==28);
  const int track=tree.createView(),thumb=tree.createView();
  tree.setParent(track,root);tree.setParent(thumb,track);
  tree.setAttribute(control,"role","slider");tree.setAttribute(thumb,"data-xaml-type","LSThumb");
  tree.node(track).layout.x=530;tree.node(track).layout.width=180;tree.node(thumb).layout.width=40;
  gea::macos::publishControlEventBounds(control);
  assert(std::stof(tree.getAttribute(control,"data-gea-x"))==550);
  assert(std::stof(tree.getAttribute(control,"data-gea-width"))==140);
  // The renderer must reflect a Gea checkmark's visibility in both directions,
  // without removing its arranged box.
  NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,200,200)];
  tree.node(root).layout.width=200;tree.node(root).layout.height=200;
  const int mark=tree.createView();tree.setParent(mark,root);
  tree.node(mark).layout.width=16;tree.node(mark).layout.height=16;
  auto &renderer=gea::macos::MacosRenderer::instance();
  renderer.sync(host,root);
  NSView *nativeRoot=host.subviews.firstObject;
  NSView *nativeMark=nativeRoot.subviews.lastObject;
  assert(nativeMark && !nativeMark.hidden);
  tree.node(mark).style.visibility=1;renderer.sync(host,root);
  assert(nativeMark.hidden && nativeMark.frame.size.width==16);
  tree.node(mark).style.visibility=0;renderer.sync(host,root);
  assert(!nativeMark.hidden);
  renderer.teardown();
  resetDocumentEventListeners();
  std::puts("PASS: Gea document keyboard routing, UTF-8 text commit, live control bounds; no NSControl editor.");
 }
}

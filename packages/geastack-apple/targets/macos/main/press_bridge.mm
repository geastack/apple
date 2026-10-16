#import "press_bridge.h"

#include "ui/tree_internal.h"
#include "events.h"

#include <cstring>

#include "ui/node.h"
#include "macos_key_event.h"
#include "macos_control_admission.h"

namespace {
struct NativePress {
 gea::framework::identity::Owner binding, owner;
 int node = -1;
 NSUInteger ticket = 0;
 bool tracking = false, active = false, completed = false;
 bool pointerGesture = false;
 int button = -1;
 std::uint32_t buttons = 0;
 bool current() const {
  return owner==binding && gea::framework::identity::current(node,owner);
 }
 void emit(gea::framework::events::PointerEventType type) const {
  if(!current())return;
  gea::framework::events::PointerEvent event;
  event.type=type;event.targetId=node;event.pointerId=1;
  if(pointerGesture){
   event.button=type==gea::framework::events::PointerEventType::PointerCancel?-1:button;
   event.buttons=type==gea::framework::events::PointerEventType::TouchStart?buttons:0;
  }
  gea::embedded::ui::Tree::instance().dispatchEvent(event);
 }
};
}
extern "C" void gea_macos_fire_press_for_node(int nodeId)
{
 const auto owner=gea::framework::identity::node(nodeId);
 if(!gea::macos::controlAdmitted(nodeId,owner))return;
 gea::framework::events::PointerEvent event{};
 event.type=gea::framework::events::PointerEventType::Click;
 event.targetId=nodeId;
 gea::embedded::ui::Tree::instance().dispatchEvent(event);
}

// Headless equivalent of a keystroke into the first `<input>` / `<textarea>`:
// write the text into the node's `value` attribute and dispatch
// `PointerEventType::Input`, which is exactly what `GeaTextAreaView
// textDidChange:` / `GeaTextFieldView controlTextDidChange:` do for a real key
// event (macos_renderer.mm). Driven by GEA_MACOS_SYNTH_INPUT so the text-input
// path can be exercised in a shell with no Accessibility permission — posting
// synthetic key events through CGEvent needs one, so without this there is no
// way to regression-test "typing does not crash" from a script.
// Returns the node it targeted, or -1 when the tree has no text input.
extern "C" int gea_macos_fire_input_for_node(int nodeId, const char *text)
{
	using gea::framework::events::PointerEvent;
	using gea::framework::events::PointerEventType;
	auto &tree = gea::embedded::ui::Tree::instance();
	int target = nodeId;
	if (target < 0) {
		for (int i = 0; i < tree.nodeCount(); i++) {
			const char *tag = tree.tagName(i);
			if (!tag) continue;
			if (std::strcmp(tag, "input") == 0 || std::strcmp(tag, "textarea") == 0) { target = i; break; }
		}
	}
	if (target < 0 || target >= tree.nodeCount()) return -1;
	if (!gea::macos::controlAdmitted(target, gea::framework::identity::node(target))) return -1;
	tree.setAttribute(target, "value", text ? text : "");
	PointerEvent ev;
	ev.type = PointerEventType::Input;
	ev.targetId = target;
	ev.keyCode = 0;
	tree.dispatchEvent(ev);
	return target;
}

@interface GeaRetiredPress ()
- (instancetype)initWithState:(const NativePress &)state;
@end
@implementation GeaRetiredPress
- (instancetype)initWithState:(const NativePress &)state {
 if((self=[super init]))_geaRetiredState=new NativePress(state);
 return self;
}
- (void)dealloc {delete static_cast<NativePress *>(_geaRetiredState);}
- (void)emitCancellation {
 auto &state=*static_cast<NativePress *>(_geaRetiredState);
 if(!state.active || state.completed)return;
 state.active=false;state.completed=true;
 state.emit(gea::framework::events::PointerEventType::PointerCancel);
}
@end

@implementation PressBridge
- (instancetype)init {
 if((self=[super init])){_nodeId=-1;_geaPressState=new NativePress;}
 return self;
}
- (void)dealloc { delete static_cast<NativePress *>(_geaPressState); }
- (void)setNodeId:(int)nodeId {
 auto &state=*static_cast<NativePress *>(_geaPressState);
 auto binding=gea::framework::identity::node(nodeId);
 if(_nodeId!=nodeId || state.binding!=binding)[self cancelPress:nil];
 _nodeId=nodeId;state.binding=std::move(binding);
}
- (NSUInteger)beginPress:(id)sender {
 (void)sender;[self cancelPress:nil];
 auto &state=*static_cast<NativePress *>(_geaPressState);
 state.node=_nodeId;state.owner=state.binding;
 if(!state.current() || !gea::macos::controlAdmitted(state.node,state.owner))return 0;
 ++state.ticket;if(!state.ticket)++state.ticket;
 state.tracking=true;state.active=true;state.completed=false;
 state.pointerGesture=false;state.button=-1;state.buttons=0;
 const auto ticket=state.ticket;
 return ticket;
}
- (NSUInteger)beginKeyboardPress:(id)sender { return [self beginPress:sender]; }
- (NSUInteger)beginPointerPress:(NSEvent *)event {
 if(!event || (event.type!=NSEventTypeLeftMouseDown && event.type!=NSEventTypeRightMouseDown && event.type!=NSEventTypeOtherMouseDown))return 0;
 // Left/right event kinds carry the changed edge even when AppKit authored
 // mouseEventWithType reports buttonNumber zero for a right event. Other
 // events require an actual additional-button number; unknown is refused.
 const NSInteger nativeButton=event.type==NSEventTypeLeftMouseDown?0:event.type==NSEventTypeRightMouseDown?1:event.buttonNumber;
 if(nativeButton<0 || nativeButton>31 || (event.type==NSEventTypeOtherMouseDown && nativeButton<2))return 0;
 const auto ticket=[self beginPress:nil];if(!ticket)return 0;
 auto &state=*static_cast<NativePress *>(_geaPressState);
 state.pointerGesture=true;
 state.button=nativeButton==1?2:nativeButton==2?1:static_cast<int>(nativeButton);
 // Track this owned gesture's changed edge, not unrelated global mouse work.
 // A directly delivered native down event need not change pressedMouseButtons.
 state.buttons=std::uint32_t(1)<<nativeButton;
 state.emit(gea::framework::events::PointerEventType::TouchStart);
 return ticket;
}
- (void)cancelPress:(id)sender {
 (void)sender;auto &state=*static_cast<NativePress *>(_geaPressState);
 if(!state.active)return;
 state.active=false;state.completed=true;
 state.emit(gea::framework::events::PointerEventType::PointerCancel);
}
- (GeaRetiredPress *)closeInputBinding {
 auto &state=*static_cast<NativePress *>(_geaPressState);
 GeaRetiredPress *retired=[[GeaRetiredPress alloc] initWithState:state];
 _nodeId=-1;state.node=-1;state.owner={};state.binding={};
 state.active=false;state.completed=true;state.tracking=true;++state.ticket;
 return retired;
}
- (void)endPressTracking:(NSUInteger)ticket {
 auto &state=*static_cast<NativePress *>(_geaPressState);
 if(state.ticket!=ticket)return;
 [self cancelPress:nil];if(state.ticket==ticket)state.tracking=false;
}
- (void)fire:(id)sender {
 auto &state=*static_cast<NativePress *>(_geaPressState);
 if(!gea::macos::controlAdmitted(_nodeId,state.binding)){[self cancelPress:nil];return;}
 if([sender isKindOfClass:[NSControl class]] && ![(NSControl *)sender isEnabled]) {
  [self cancelPress:nil];return;
 }
 if(!state.tracking){
  if(gea::framework::identity::current(_nodeId,state.binding))gea_macos_fire_press_for_node(_nodeId);
  return;
 }
 if(!state.active || state.completed)return; // native action repeats/echo
 const auto ticket=state.ticket;
 state.active=false;state.completed=true;
 if(!state.current())return;
 if(state.pointerGesture)state.emit(gea::framework::events::PointerEventType::TouchEnd);
 if(state.ticket==ticket && state.current() && gea::macos::controlAdmitted(state.node,state.owner))state.emit(gea::framework::events::PointerEventType::Click);
}
@end

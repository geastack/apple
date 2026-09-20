#import "press_bridge.h"

#include "ui/tree_internal.h"
#include "events.h"

#include <cstring>

extern "C" void gea_macos_fire_press_for_node(int nodeId)
{
	using gea::framework::events::PointerEvent;
	using gea::framework::events::PointerEventType;
	if (nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (nodeId >= tree.nodeCount()) return;

	// A native click on macOS corresponds to a full press-and-release cycle.
	// Apps may listen for any of these — the browser equivalent fires the
	// whole sequence too — so dispatch them in browser order:
	//   touchstart → touchend → click
	// This way apps written for the ESP32 touchscreen (which only sees
	// touchstart/touchend) still respond to mouse clicks, and JSX onClick
	// handlers fire consistently with the web target.
	auto fire = [&](PointerEventType type) {
		PointerEvent ev;
		ev.type = type;
		ev.targetId = nodeId;
		tree.dispatchEvent(ev);
	};
	fire(PointerEventType::TouchStart);
	fire(PointerEventType::TouchEnd);
	fire(PointerEventType::Click);
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
	tree.setAttribute(target, "value", text ? text : "");
	PointerEvent ev;
	ev.type = PointerEventType::Input;
	ev.targetId = target;
	ev.keyCode = 0;
	tree.dispatchEvent(ev);
	return target;
}

@implementation PressBridge
- (void)fire:(id)sender
{
	(void)sender;
	gea_macos_fire_press_for_node(self.nodeId);
}
@end

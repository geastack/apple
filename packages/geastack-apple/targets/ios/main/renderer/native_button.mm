#include "ios_renderer_internal.h"

#include "events.h"
#include "ui/tree_internal.h"

#include <algorithm>
#include <cmath>

extern "C" void gea_ios_touch_set_state(int touching, int x, int y);

@implementation GeaNativeButton

- (CGPoint)eventPoint
{
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId < 0 || self.nodeId >= tree.nodeCount()) return CGPointZero;
	const auto &node = tree.node(self.nodeId);
	return CGPointMake(static_cast<CGFloat>(node.layout.x + node.layout.width / 2),
	                   static_cast<CGFloat>(node.layout.y + node.layout.height / 2));
}

- (bool)dispatchPointerEvent:(gea::framework::events::PointerEventType)type activeTouch:(BOOL)activeTouch
{
	if (self.nodeId < 0) return false;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return false;

	const CGPoint point = [self eventPoint];
	gea::framework::events::PointerEvent event{};
	event.type = type;
	event.targetId = self.nodeId;
	event.pointerId = 1;
	event.x = static_cast<int>(std::lround(point.x));
	event.y = static_cast<int>(std::lround(point.y));
	event.clientX = event.x;
	event.clientY = event.y;
	event.pageX = event.x;
	event.pageY = event.y;
	event.screenX = event.x;
	event.screenY = event.y;
	event.primary = true;
	event.touchesLength = activeTouch ? 1 : 0;
	event.targetTouchesLength = activeTouch ? 1 : 0;
	event.changedTouchesLength = 1;
	event.touches[0].identifier = 1;
	event.touches[0].target = gea::framework::events::EventTarget(self.nodeId);
	event.touches[0].screenX = event.x;
	event.touches[0].screenY = event.y;
	event.touches[0].clientX = event.x;
	event.touches[0].clientY = event.y;
	event.touches[0].pageX = event.x;
	event.touches[0].pageY = event.y;
	event.targetTouches[0] = event.touches[0];
	event.changedTouches[0] = event.touches[0];
	tree.dispatchEvent(event);
	return event.defaultPrevented;
}

- (void)setNativeTouchState:(BOOL)touching
{
	const CGPoint point = [self eventPoint];
	gea_ios_touch_set_state(touching ? 1 : 0,
	                        static_cast<int>(std::lround(point.x)),
	                        static_cast<int>(std::lround(point.y)));
}

- (void)handleTouchDown:(id)sender
{
	(void)sender;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId < 0 || self.nodeId >= tree.nodeCount()) return;
	const CGPoint point = [self eventPoint];
	const int x = static_cast<int>(std::lround(point.x));
	const int y = static_cast<int>(std::lround(point.y));
	[self setNativeTouchState:YES];
	tree.pointerDown(x, y);
	[self dispatchPointerEvent:gea::framework::events::PointerEventType::TouchStart activeTouch:YES];
}

- (void)handleTouchDrag:(id)sender
{
	(void)sender;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId < 0 || self.nodeId >= tree.nodeCount()) return;
	const CGPoint point = [self eventPoint];
	const int x = static_cast<int>(std::lround(point.x));
	const int y = static_cast<int>(std::lround(point.y));
	[self setNativeTouchState:YES];
	[self dispatchPointerEvent:gea::framework::events::PointerEventType::TouchMove activeTouch:YES];
	tree.pointerMove(x, y);
}

- (void)finishTouchInside:(BOOL)inside
{
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;
	[self setNativeTouchState:NO];
	tree.pointerUp();
	[self dispatchPointerEvent:gea::framework::events::PointerEventType::TouchEnd activeTouch:NO];
	if (inside) {
		[self dispatchPointerEvent:gea::framework::events::PointerEventType::Click activeTouch:NO];
	}
}

- (void)handleTouchUpInside:(id)sender
{
	(void)sender;
	[self finishTouchInside:YES];
}

- (void)handleTouchUpOutside:(id)sender
{
	(void)sender;
	[self finishTouchInside:NO];
}

- (void)handleTouchCancel:(id)sender
{
	(void)sender;
	[self finishTouchInside:NO];
}

@end

namespace gea::ios::renderer {

namespace {

// The words a button shows: every descendant text run in document order,
// joined with spaces, skipping display:none subtrees. The same text win32
// draws as the title of a native button (buttonTitle).
NSString *buttonAccessibilityLabel(const gea::embedded::ui::Node &node)
{
	using gea::embedded::ui::kDisplayNone;
	using gea::embedded::ui::NodeType;
	auto &tree = gea::embedded::ui::Tree::instance();
	std::string text;
	std::vector<int> stack;
	for (int child = node.first_child; child >= 0; child = tree.node(child).next_sibling) stack.push_back(child);
	std::reverse(stack.begin(), stack.end());
	while (!stack.empty()) {
		const int id = stack.back();
		stack.pop_back();
		if (id < 0 || id >= tree.nodeCount()) continue;
		const auto &current = tree.node(id);
		if (current.style.display == kDisplayNone) continue;
		if (current.type == NodeType::Text && !current.text.empty()) {
			if (!text.empty()) text.push_back(' ');
			text += current.text;
		}
		std::vector<int> children;
		for (int child = current.first_child; child >= 0; child = tree.node(child).next_sibling) children.push_back(child);
		for (auto it = children.rbegin(); it != children.rend(); ++it) stack.push_back(*it);
	}
	return NSStringFromText(text);
}

}  // namespace

void applyButtonProps(GeaNativeButton *button, const gea::embedded::ui::Node &node, int nodeId)
{
	button.nodeId = nodeId;
	button.userInteractionEnabled = !(node.style.display == 1 || node.style.opacity == 0 ||
	                                  node.layout.width <= 0 || node.layout.height <= 0);
	// No UIButton title: a button's content is its children, synced as subviews
	// where the engine laid them out (the UA sheet centres them), the way win32
	// paints them. Lifting the first text child into a centred title and hiding
	// every label flattened the button to one string: weather's city chips lost
	// their temperature, and a child's own size and weight went with it.
	//
	// A UIButton is one accessibility element and VoiceOver never reads its
	// subviews, so without a title it announced an unnamed "button" for every
	// chip. Spell the children's text out as the label instead.
	NSString *label = buttonAccessibilityLabel(node);
	if (![button.accessibilityLabel isEqualToString:label]) button.accessibilityLabel = label;
}

}  // namespace gea::ios::renderer

#include "ios_renderer_internal.h"

#include "events.h"
#include "font_registry.h"
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

const gea::embedded::ui::Node *firstVisibleTextChild(int nodeId)
{
	using gea::embedded::ui::NodeType;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return nullptr;
	const auto &buttonNode = tree.node(nodeId);
	for (int child = buttonNode.first_child; child >= 0; child = tree.node(child).next_sibling) {
		const auto &childNode = tree.node(child);
		if (childNode.type == NodeType::Text && childNode.style.display != 1) return &childNode;
	}
	return nullptr;
}

NSAttributedString *attributedTitleForTextChild(const gea::embedded::ui::Node &textNode, CGFloat scale)
{
	NSString *raw = NSStringFromText(textNode.text);
	const CGFloat fontSize = std::max<CGFloat>(1.0, static_cast<CGFloat>(textNode.style.font_size > 0 ? textNode.style.font_size : 16) * scale);
	UIFont *font = gea::ios::fontForId(textNode.style.font_id, fontSize);
	UIColor *color = rgb565ToUIColor(textNode.style.text_color);
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.alignment = textAlignmentForStyle(textNode.style.text_align);
	paragraph.lineBreakMode = NSLineBreakByWordWrapping;
	NSMutableDictionary *attrs = textAttributes(font, color, textNode.style.text_decoration);
	attrs[NSParagraphStyleAttributeName] = paragraph;
	return [[NSAttributedString alloc] initWithString:raw attributes:attrs];
}

}  // namespace

void applyButtonProps(GeaNativeButton *button, const gea::embedded::ui::Node &node, int nodeId, CGFloat scale)
{
	button.nodeId = nodeId;
	button.userInteractionEnabled = !(node.style.display == 1 || node.style.opacity == 0 ||
	                                  node.layout.width <= 0 || node.layout.height <= 0);
	button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	button.titleLabel.numberOfLines = 0;
	button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

	const gea::embedded::ui::Node *titleNode = firstVisibleTextChild(nodeId);
	if (titleNode && !titleNode->text.empty()) {
		button.titleLabel.hidden = NO;
		[button setAttributedTitle:attributedTitleForTextChild(*titleNode, scale) forState:UIControlStateNormal];
	} else {
		button.titleLabel.hidden = YES;
		[button setAttributedTitle:nil forState:UIControlStateNormal];
	}
}

}  // namespace gea::ios::renderer

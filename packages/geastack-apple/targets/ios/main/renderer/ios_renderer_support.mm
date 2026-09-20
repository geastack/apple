#include "ios_renderer_internal.h"

#include "display.h"
#include "events.h"
#include "pixel.h"
#include "ui/tree_internal.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

extern "C" void gea_ios_touch_set_state(int touching, int x, int y);

namespace gea::ios::renderer {

UIColor *rgb565ToUIColor(gea::framework::graphics::pixel::native_t color)
{
	// Style colours are native pixels (RGBA8888 on iOS) — unpack the full 8-bit
	// channels so native UIKit views render true colour, not 565-quantized.
	int r, g, b, a;
	gea::framework::graphics::pixel::unpackNative8(color, &r, &g, &b, &a);
	return [UIColor colorWithRed:static_cast<CGFloat>(r) / 255.0
	                       green:static_cast<CGFloat>(g) / 255.0
	                        blue:static_cast<CGFloat>(b) / 255.0
	                       alpha:1.0];
}

CGFloat canvasScaleForView(UIView *view)
{
	auto *canvas = gea::platform::display::Display::canvas();
	if (!view || !canvas || canvas->width() <= 0 || view.bounds.size.width <= 0) return 1.0;
	return view.bounds.size.width / static_cast<CGFloat>(canvas->width());
}

void dispatchSyntheticTap(UIView *rootView, CGPoint point)
{
	auto *canvas = gea::platform::display::Display::canvas();
	if (!rootView || !canvas || canvas->width() <= 0 || canvas->height() <= 0) return;
	const CGFloat scale = canvasScaleForView(rootView);
	int x = std::clamp(static_cast<int>(std::lround(point.x / std::max<CGFloat>(scale, 0.0001))),
	                   0,
	                   std::max(0, canvas->width() - 1));
	int y = std::clamp(static_cast<int>(std::lround(point.y / std::max<CGFloat>(scale, 0.0001))),
	                   0,
	                   std::max(0, canvas->height() - 1));

	auto fireTouch = [&](gea::framework::events::TouchPhase phase, bool touching) {
		gea_ios_touch_set_state(touching ? 1 : 0, x, y);
		gea::framework::events::Event event{};
		event.type = gea::framework::events::EventType::Touch;
		event.touchPhase = phase;
		event.touching = touching;
		event.x = x;
		event.y = y;
		gea::framework::events::TouchRuntime::dispatchEvent(event);
	};

	gea::framework::events::TouchRuntime::resetGestureState();
	fireTouch(gea::framework::events::TouchPhase::Down, true);
	fireTouch(gea::framework::events::TouchPhase::Up, false);
}

bool isScrollableNode(const gea::embedded::ui::Node &node)
{
	using gea::embedded::ui::NodeType;
	if (node.type == NodeType::VirtualList) return node.layout.scroll_content_height > node.layout.height;
	return node.style.overflow == 2 && node.layout.scroll_content_height > node.layout.height;
}

NSMutableDictionary<NSNumber *, UIView *> *nodeIdToView()
{
	static NSMutableDictionary<NSNumber *, UIView *> *map = [NSMutableDictionary new];
	return map;
}

NSString *NSStringFromText(const std::string &value)
{
	return [NSString stringWithUTF8String:value.empty() ? "" : value.c_str()] ?: @"";
}

NSTextAlignment textAlignmentForStyle(int align)
{
	switch (align) {
	case 1: return NSTextAlignmentCenter;
	case 2: return NSTextAlignmentRight;
	default: return NSTextAlignmentLeft;
	}
}

static void addTextDecorationAttributes(NSMutableDictionary *attrs, int textDecoration)
{
	if (!attrs) return;
	NSNumber *style = @((NSInteger)NSUnderlineStyleSingle);
	if (textDecoration == 1) {
		attrs[NSUnderlineStyleAttributeName] = style;
	} else if (textDecoration == 2) {
		attrs[NSStrikethroughStyleAttributeName] = style;
	}
}

NSMutableDictionary *textAttributes(UIFont *font, UIColor *color, int textDecoration)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	attrs[NSFontAttributeName] = font ?: [UIFont systemFontOfSize:16];
	attrs[NSForegroundColorAttributeName] = color ?: UIColor.whiteColor;
	addTextDecorationAttributes(attrs, textDecoration);
	return attrs;
}

}  // namespace gea::ios::renderer

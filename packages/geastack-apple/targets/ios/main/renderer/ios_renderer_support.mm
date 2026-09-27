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

UIColor *rgb565ToUIColor(gea::framework::graphics::pixel::native_t color, std::uint8_t alpha)
{
	// Style colours are native pixels (RGBA8888 on iOS) — unpack the full 8-bit
	// channels so native UIKit views render true colour, not 565-quantized.
	//
	// The pixel's own alpha byte is always 255: cssColorStyleValue packs rgb only,
	// deliberately, so a colour means the same thing on a 565 board as here. The
	// CSS alpha comes in as the `alpha` argument from the caller's style field.
	int r, g, b, a;
	gea::framework::graphics::pixel::unpackNative8(color, &r, &g, &b, &a);
	return [UIColor colorWithRed:static_cast<CGFloat>(r) / 255.0
	                       green:static_cast<CGFloat>(g) / 255.0
	                        blue:static_cast<CGFloat>(b) / 255.0
	                       alpha:static_cast<CGFloat>(alpha) / 255.0];
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

// Only a box that scrolls VERTICALLY becomes a UIScrollView, and only by its
// own `overflow-y: auto/scroll` -- not the `auto` CSS computes for a visible axis
// beside a scrolling one (weather's hour rail says `overflow-y: visible`), which
// is the raw field win32 keys on too. Every touch lands on GeaDisplayView and
// the engine does the scrolling, so for a sideways rail a UIScrollView only
// added a second shift: the engine already places the children at -scroll_x
// (layout.cpp) and contentOffset.x moved them again, so the city chips travelled
// twice as far as the finger. Those rails stay plain views, clipped by their
// overflow, and follow scroll_x through their children's frames.
bool isScrollableNode(const gea::embedded::ui::Node &node)
{
	using gea::embedded::ui::NodeType;
	if (node.type == NodeType::VirtualList) return node.layout.scroll_content_height > node.layout.height;
	return node.style.overflow_y == 2 && node.layout.scroll_content_height > node.layout.height;
}

// CSS border-radius on a layer, resolved the way macOS resolveRadii does it (and
// the engine's resolvedBorderRadii8): a percent radius (border_radius_percent, a
// separate array from the px radii) against the box, then the CSS overlap rule
// scaling every radius down until adjacent corners fit their side. Weather's
// pills say 666px; handed to cornerRadius raw that is a ~980pt radius on a 25pt
// box, which Core Animation does not draw as a pill -- the topbar buttons and the
// forecast tabs were not there at all. A CALayer has one circular radius, so an
// elliptical corner takes its shorter axis and unequal corners share their mean,
// masked to the corners that are rounded at all.
void applyCornerRadius(CALayer *layer, const gea::embedded::ui::Node &node, CGFloat scale)
{
	const double width = std::max(0, static_cast<int>(node.layout.width));
	const double height = std::max(0, static_cast<int>(node.layout.height));
	double rx[4]{};
	double ry[4]{};
	for (int i = 0; i < 4; ++i) {
		if (node.style.border_radius_percent[i] != gea::embedded::ui::kUnset) {
			const double p = static_cast<double>(node.style.border_radius_percent[i]) / 1000.0;
			rx[i] = std::max(0.0, width * p);
			ry[i] = std::max(0.0, height * p);
		} else {
			rx[i] = ry[i] = std::max(0, static_cast<int>(node.style.border_radius[i]));
		}
	}
	double fit = 1.0;
	const auto constrain = [&](double side, double sum) {
		if (side > 0.0 && sum > side) fit = std::min(fit, side / sum);
	};
	constrain(width, rx[0] + rx[1]);
	constrain(width, rx[3] + rx[2]);
	constrain(height, ry[0] + ry[3]);
	constrain(height, ry[1] + ry[2]);

	// CSS corner order: top-left, top-right, bottom-right, bottom-left. A UIKit
	// layer's y grows downward, so MinY is the top edge.
	static const CACornerMask kCorners[4] = {kCALayerMinXMinYCorner, kCALayerMaxXMinYCorner,
	                                         kCALayerMaxXMaxYCorner, kCALayerMinXMaxYCorner};
	CACornerMask mask = 0;
	double sum = 0.0;
	int rounded = 0;
	for (int i = 0; i < 4; ++i) {
		const double r = std::min(rx[i], ry[i]) * fit;
		if (r <= 0.0) continue;
		mask |= kCorners[i];
		sum += r;
		rounded++;
	}
	const CGFloat radius = rounded > 0 ? static_cast<CGFloat>(sum / rounded) * scale : 0;
	if (std::fabs(layer.cornerRadius - radius) > 0.01) layer.cornerRadius = radius;
	if (rounded > 0 && layer.maskedCorners != mask) layer.maskedCorners = mask;
}

// Paint order among siblings is CSS stacking order: z-index first, DOM order
// among equals -- the stable sort win32 paints with (childrenByStacking).
// Subviews were only ever appended, so a later sibling covered an earlier one
// whatever its z-index: weather's .hero-stage (z-index 2, the 220px sun) painted
// over .place-block (4). The view tree is touched only when the order it has
// is not that order; `parent` may hold private subviews of its own (a
// UIButton's title, a scroll view's debug markers), which is why the check is a
// subsequence one.
void stackChildViews(UIView *parent, std::vector<std::pair<int, UIView *>> &children)
{
	std::stable_sort(children.begin(), children.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	std::size_t next = 0;
	for (UIView *subview in parent.subviews) {
		if (next < children.size() && subview == children[next].second) next++;
	}
	if (next == children.size()) return;
	for (const auto &child : children) [parent bringSubviewToFront:child.second];
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

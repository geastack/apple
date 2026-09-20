#import "canvas_view.h"

#include "ui/tree_internal.h"
#include "canvas.h"
#include "events.h"
#include "host/display_orientation.h"
#include "pixel.h"

#include <algorithm>
#include <cmath>

extern "C" void gea_macos_touch_set_state(int touching, int x, int y);

namespace {

// Single shared scratch buffer for RGB565→RGBA8888 expansion. Sized lazily to
// the largest canvas seen. -drawRect: is main-thread-only so no locking.
std::uint8_t *g_scratch = nullptr;
size_t g_scratchBytes = 0;

std::uint8_t *ensureScratch(size_t bytes)
{
	if (g_scratchBytes < bytes) {
		void *grown = std::realloc(g_scratch, bytes);
		if (!grown) return nullptr;
		g_scratch = static_cast<std::uint8_t *>(grown);
		g_scratchBytes = bytes;
	}
	return g_scratch;
}

}  // namespace

@implementation GeaCanvasView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_nodeId = -1;
	}
	return self;
}

// Stay UNFLIPPED. The canvas pixel buffer is stored top-down (row 0 = top),
// which is what CGContextDrawImage expects when the destination context uses
// default Quartz (bottom-up) coords. Setting isFlipped:YES would make AppKit
// apply an implicit Y-inversion and the image would render upside-down. The
// renderer that positions this view already converts CSS top-left coords to
// AppKit bottom-left when computing our frame, so unflipped is correct.
- (BOOL)isFlipped { return NO; }

// Mouse → framework touch events, mirroring the iOS renderer's dispatchTouch
// flow. Canvas apps (maps, games) read gesture coordinates off onPointerDown/
// Move/Up — the AppKit click recognizer only fires coordinate-less presses, so
// without this a drag never pans and every tap lands at 0,0. The recognizer's
// delegate declines canvas views, so events arrive here exactly once.
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
}

- (void)dispatchMousePhase:(gea::framework::events::TouchPhase)phase
                  touching:(bool)touching
                     event:(NSEvent *)event
{
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;
	const auto *canvas = tree.canvas(self.nodeId);
	const NSRect bounds = self.bounds;
	if (!canvas || bounds.size.width <= 0 || bounds.size.height <= 0) return;

	// View point (bottom-up) → top-down surface coords, scaled to the canvas
	// pixel grid (drawRect stretches the canvas into the view bounds, so input
	// must apply the inverse of that stretch to stay aligned).
	const NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	const double scaleX = canvas->width() / bounds.size.width;
	const double scaleY = canvas->height() / bounds.size.height;
	const int lx = std::clamp((int)std::lround(p.x * scaleX), 0, canvas->width() - 1);
	const int ly = std::clamp((int)std::lround((bounds.size.height - 1 - p.y) * scaleY), 0,
	                          canvas->height() - 1);

	// The latest-move cache holds PANEL-NATIVE coordinates (the hardware touch
	// controller contract): the dispatcher re-reads Move coords from it through
	// transformTouchToLogical, so store the inverse-transformed point.
	namespace od = gea::framework::display::detail;
	using gea::framework::display::DisplayOrientation;
	int px = lx;
	int py = ly;
	switch (od::DisplayOrientationState::orientation()) {
	case DisplayOrientation::LandscapePrimary:
		px = ly;
		py = od::DisplayOrientationState::nativeHeight() - 1 - lx;
		break;
	case DisplayOrientation::LandscapeSecondary:
		px = od::DisplayOrientationState::nativeWidth() - 1 - ly;
		py = lx;
		break;
	case DisplayOrientation::PortraitSecondary:
		px = od::DisplayOrientationState::nativeWidth() - 1 - lx;
		py = od::DisplayOrientationState::nativeHeight() - 1 - ly;
		break;
	case DisplayOrientation::PortraitPrimary:
	default:
		break;
	}
	gea_macos_touch_set_state(touching ? 1 : 0, px, py);

	gea::framework::events::Event ev{};
	ev.type = gea::framework::events::EventType::Touch;
	ev.touchPhase = phase;
	ev.touching = touching;
	ev.x = lx;
	ev.y = ly;
	ev.pointerId = 0;
	gea::framework::events::TouchRuntime::dispatchEvent(ev);
}

- (void)mouseDown:(NSEvent *)event
{
	[self dispatchMousePhase:gea::framework::events::TouchPhase::Down touching:true event:event];
}

- (void)mouseDragged:(NSEvent *)event
{
	[self dispatchMousePhase:gea::framework::events::TouchPhase::Move touching:true event:event];
}

- (void)mouseUp:(NSEvent *)event
{
	[self dispatchMousePhase:gea::framework::events::TouchPhase::Up touching:false event:event];
}

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;
	const auto *canvas = tree.canvas(self.nodeId);
	if (!canvas) return;
	const std::uint16_t *src = canvas->pixels();
	const int w = canvas->width();
	const int h = canvas->height();
	if (!src || w <= 0 || h <= 0) return;

	const size_t bytes = (size_t)w * (size_t)h * 4;
	std::uint8_t *dst = ensureScratch(bytes);
	if (!dst) return;
	for (int i = 0; i < w * h; i++) {
		int r, g, b;
		gea::framework::graphics::pixel::unpackRgb565(src[i], &r, &g, &b);
		dst[i * 4 + 0] = static_cast<std::uint8_t>((r * 255 + 15) / 31);
		dst[i * 4 + 1] = static_cast<std::uint8_t>((g * 255 + 31) / 63);
		dst[i * 4 + 2] = static_cast<std::uint8_t>((b * 255 + 15) / 31);
		dst[i * 4 + 3] = 0xFF;
	}

	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, dst, bytes, NULL);
	const uint32_t bitmapInfo = (uint32_t)kCGImageAlphaNoneSkipLast | (uint32_t)kCGBitmapByteOrder32Big;
	CGImageRef img = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)w * 4,
	                               cs, bitmapInfo,
	                               provider, NULL, false, kCGRenderingIntentDefault);

	CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
	CGContextDrawImage(ctx, NSRectToCGRect(self.bounds), img);

	CGImageRelease(img);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(cs);
}

@end

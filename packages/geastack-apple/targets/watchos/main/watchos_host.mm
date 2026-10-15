#import <Foundation/Foundation.h>

#include "watchos_bridge.h"

#include "app.h"
#include "canvas.h"
#include "css/declarative.h"
#include "display.h"
#include "event.h"
#include "events.h"
#include "pixel.h"
#include "ui/style.h"
#include "ui/tree_internal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

// The watchOS shell reuses the iOS host backends for everything below the
// window: the RGBA8888 framebuffer display (ios_display.mm), the frame clock
// (ios_timers.mm), touch state and CoreMotion (ios_sensors.mm). watchOS has no
// UIView hierarchy an app can own, so there is no native view renderer here;
// gea paints the whole UI into the framebuffer and SwiftUI shows it as an image.
extern "C" int gea_embedded_now_ms(void);
extern "C" void gea_ios_display_set_viewport_size(int width, int height);
extern "C" const std::uint32_t *gea_ios_display_presented_pixels();
extern "C" std::uint32_t gea_ios_display_presented_generation();
extern "C" void gea_ios_touch_set_state(int touching, int x, int y);

namespace {

bool g_started = false;
int g_width_px = 0;
int g_height_px = 0;
double g_scale = 1.0;
std::uint32_t g_last_generation = 0;
// Sub-pixel Crown rotation not yet applied as scroll.
double g_crown_pending_px = 0.0;

int clampToCanvas(double value, int extent)
{
	const int rounded = static_cast<int>(std::lround(value));
	return std::clamp(rounded, 0, std::max(0, extent - 1));
}

// Where a watch screen keeps content clear of the system clock and its rounded
// corners, in panel pixels. watchOS exposes neither the corner shape nor the
// clock's extent, and its safe area reserves far more (53pt of a 248pt-tall
// 46mm screen at the top alone), so these are measured per panel size: corners
// from each Simulator device type's framebufferMask, the clock from a blank app
// on watchOS 26.5. `top` clears the clock with a 4px margin; `side` is how far
// the corner cuts in at that depth; `bottom` is where the bottom corner cuts in
// no further than `side`; `radius` is how deep the corner curve runs.
struct WatchScreenInsets {
	int width, height;
	int top, side, bottom, radius;
};

constexpr WatchScreenInsets kWatchScreenInsets[] = {
	{324, 394, 46, 2, 45, 57},   // 40mm SE, Series 4-6
	{352, 430, 56, 4, 54, 78},   // 41mm Series 7-9
	{368, 448, 54, 3, 52, 72},   // 44mm SE, Series 4-6
	{374, 446, 60, 6, 60, 94},   // 42mm Series 10+
	{396, 484, 62, 4, 59, 85},   // 45mm Series 7-9
	{410, 502, 70, 9, 69, 126},  // 49mm Ultra, Ultra 2
	{416, 496, 67, 7, 67, 108},  // 46mm Series 10+
	{422, 514, 72, 10, 71, 135}, // 49mm Ultra 3
};

// An unlisted panel borrows the nearest listed one's insets, scaled by height.
WatchScreenInsets insetsForPanel(int width, int height)
{
	const WatchScreenInsets *nearest = &kWatchScreenInsets[0];
	for (const auto &entry : kWatchScreenInsets) {
		if (entry.width == width && entry.height == height) return entry;
		if (std::abs(entry.height - height) < std::abs(nearest->height - height)) nearest = &entry;
	}
	const double k = static_cast<double>(height) / nearest->height;
	auto scaled = [k](int v) { return static_cast<int>(std::lround(v * k)); };
	return {width, height, scaled(nearest->top), scaled(nearest->side), scaled(nearest->bottom), scaled(nearest->radius)};
}

// Publishes the insets as `:root` custom properties in CSS px, registered ahead
// of the app's own stylesheet so they resolve on the first styled mount. Apps
// read them with a fallback for other targets: `var(--gea-safe-top, 4px)`.
void registerScreenInsetProperties(int width, int height)
{
	using namespace gea::embedded::ui;
	const WatchScreenInsets insets = insetsForPanel(width, height);
	const double cssPx = GEA_EMBEDDED_CSS_LAYOUT_DEVICE_PIXEL_RATIO;
	auto publish = [cssPx](const char *name, int panelPx) {
		StyleSheet::instance().registerStaticCustomLengthRule(StaticStyleSelectorKind::Selector, ":root", name,
		                                                      {StaticStyleLengthUnit::Px, static_cast<float>(panelPx / cssPx)}, "");
	};
	publish("--gea-safe-top", insets.top);
	publish("--gea-safe-right", insets.side);
	publish("--gea-safe-bottom", insets.bottom);
	publish("--gea-safe-left", insets.side);
	publish("--gea-screen-radius", insets.radius);
}

}  // namespace

extern "C" void gea_watchos_start(int widthPx, int heightPx, double scale)
{
	// Application::init runs the app's top level, so it happens once; a watch
	// screen never changes size under a running app.
	if (g_started || widthPx <= 0 || heightPx <= 0) return;
	g_width_px = widthPx;
	g_height_px = heightPx;
	g_scale = scale > 0 ? scale : 1.0;
	gea_ios_display_set_viewport_size(widthPx, heightPx);
	gea::platform::display::Display::init();
	registerScreenInsetProperties(widthPx, heightPx);
	// The canvas is physical pixels, so `100vw` is the full screen and text is
	// rasterised at panel resolution. CSS `px` scale by the build's layout
	// ratio, which the font atlases were baked at too.
	gea::framework::app::Application::init(widthPx, heightPx, GEA_EMBEDDED_CSS_LAYOUT_DEVICE_PIXEL_RATIO);
	g_started = true;
	g_last_generation = gea_ios_display_presented_generation() - 1;
}

extern "C" int gea_watchos_frame(void)
{
	if (!g_started) return 0;
	const int nowMs = gea_embedded_now_ms();
	gea::framework::app::Application::frame(nowMs);
	// Drive the CSS animation clock the way the embedded runtime loop
	// (core/runtime.cpp) and macos_main.mm do; this shell does not compile that
	// loop, so without it `data-anim` and @keyframes animations never start and
	// every animated app freezes on its first frame. Declarative animations are
	// started once, after the app has mounted.
	static bool declarativeAnimationsStarted = false;
	if (!declarativeAnimationsStarted && gea::embedded::ui::Tree::instance().mountedRoot() >= 0) {
		declarativeAnimationsStarted = true;
		gea::css::DeclarativeAnimations::scanAndStart(static_cast<std::uint32_t>(nowMs));
	}
	gea::embedded::ui::StyleSheet::instance().startCssAnimations(static_cast<std::uint32_t>(nowMs));
	gea::css::AnimationEngine::instance().tick(static_cast<std::uint32_t>(nowMs));
	const std::uint32_t generation = gea_ios_display_presented_generation();
	if (generation == g_last_generation) return 0;
	g_last_generation = generation;
	return 1;
}

extern "C" CGImageRef gea_watchos_copy_frame_image(void)
{
	if (!g_started) return nullptr;
	auto *canvas = gea::platform::display::Display::canvas();
	const std::uint32_t *pixels = gea_ios_display_presented_pixels();
	if (!canvas || !pixels) return nullptr;
	const int w = canvas->width();
	const int h = canvas->height();
	if (w <= 0 || h <= 0) return nullptr;

	// The framebuffer keeps changing under the next frame, so the image owns a
	// copy. Bytes are R,G,B,A per pixel -- the same layout ios_main.mm draws.
	const std::size_t bytes = static_cast<std::size_t>(w) * static_cast<std::size_t>(h) * 4;
	CFDataRef data = CFDataCreate(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(pixels), static_cast<CFIndex>(bytes));
	if (!data) return nullptr;
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CFRelease(data);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	const uint32_t bitmapInfo = static_cast<uint32_t>(kCGImageAlphaNoneSkipLast) |
	                            static_cast<uint32_t>(kCGBitmapByteOrder32Big);
	CGImageRef image = CGImageCreate(static_cast<std::size_t>(w), static_cast<std::size_t>(h),
	                                 8, 32, static_cast<std::size_t>(w) * 4,
	                                 colorSpace, bitmapInfo, provider, nullptr, false,
	                                 kCGRenderingIntentDefault);
	CGColorSpaceRelease(colorSpace);
	CGDataProviderRelease(provider);
	return image;
}

extern "C" void gea_watchos_touch(GeaWatchTouchPhase phase, double xPoints, double yPoints)
{
	using gea::framework::events::TouchPhase;
	if (!g_started) return;
	TouchPhase touchPhase = TouchPhase::Move;
	switch (phase) {
	case GeaWatchTouchDown: touchPhase = TouchPhase::Down; break;
	case GeaWatchTouchMove: touchPhase = TouchPhase::Move; break;
	case GeaWatchTouchUp: touchPhase = TouchPhase::Up; break;
	}
	const bool touching = touchPhase != TouchPhase::Up;
	const int x = clampToCanvas(xPoints * g_scale, g_width_px);
	const int y = clampToCanvas(yPoints * g_scale, g_height_px);
	gea_ios_touch_set_state(touching ? 1 : 0, x, y);

	gea::framework::events::Event event{};
	event.type = gea::framework::events::EventType::Touch;
	event.touchPhase = touchPhase;
	event.touching = touching;
	event.x = x;
	event.y = y;
	event.pointerId = 0;
	gea::framework::events::TouchRuntime::dispatchEvent(event);
}

extern "C" void gea_watchos_crown(double deltaPoints)
{
	if (!g_started) return;
	// The Crown scrolls like the Up/Down buttons on touchless boards: the first
	// vertical scroll container, through the same scroll path as a touch drag,
	// so <virtual-list> slots recycle as they do under a finger. Scroll offsets
	// are canvas pixels; fractions carry over to the next rotation event.
	g_crown_pending_px += deltaPoints * g_scale;
	const int dy = static_cast<int>(g_crown_pending_px);
	if (dy == 0) return;
	g_crown_pending_px -= dy;
	if (!gea::embedded::ui::Tree::instance().scrollByKeyStep(dy)) g_crown_pending_px = 0.0;
}

extern "C" int gea_watchos_scroll_metrics(double *topPoints, double *maxPoints)
{
	if (!g_started) return 0;
	int top = 0;
	int max = 0;
	if (!gea::embedded::ui::Tree::instance().keyStepScrollMetrics(&top, &max)) return 0;
	*topPoints = top / g_scale;
	*maxPoints = max / g_scale;
	return 1;
}

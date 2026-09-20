#import <UIKit/UIKit.h>

#include "canvas.h"
#include "display.h"
#include "host/display_orientation.h"
#include "pixel.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

// iOS renders into a full-colour RGBA8888 framebuffer (not RGB565). The build
// sets GEA_EMBEDDED_PIXEL_FORMAT=GEA_PIXEL_RGBA8888, so pixel::native_t is a
// 32-bit pixel and the Canvas operates on it natively (no 565 quantization);
// these pixels go straight into a CGImage. g_framebuffer is std::uint32_t* —
// identical to native_t under that build flag — so bindPixels binds it directly.
gea::framework::graphics::Canvas g_canvas;
std::uint32_t *g_framebuffer = nullptr;
std::uint32_t *g_presented_framebuffer = nullptr;
std::uint8_t g_alpha = 255;
int g_brightness = 100;
int g_canvas_width = gea::platform::display::kWidth;
int g_canvas_height = gea::platform::display::kHeight;
int g_flush_rows = 32;
int g_flush_depth = 2;
int g_flush_calls = 0;
int g_flush_rects = 0;
int g_flush_pixels = 0;

void ensure_canvas()
{
	if (g_framebuffer && g_canvas.width() == g_canvas_width && g_canvas.height() == g_canvas_height) return;
	std::free(g_framebuffer);
	std::free(g_presented_framebuffer);
	g_framebuffer = static_cast<std::uint32_t *>(std::calloc(static_cast<std::size_t>(g_canvas_width) * g_canvas_height,
	                                                        sizeof(std::uint32_t)));
	g_presented_framebuffer = static_cast<std::uint32_t *>(std::calloc(static_cast<std::size_t>(g_canvas_width) * g_canvas_height,
	                                                                  sizeof(std::uint32_t)));
	if (!g_framebuffer || !g_presented_framebuffer) {
		std::free(g_framebuffer);
		std::free(g_presented_framebuffer);
		g_framebuffer = nullptr;
		g_presented_framebuffer = nullptr;
		g_canvas.bindPixels(nullptr, 0, 0);
		return;
	}
	g_canvas.bindPixels(g_framebuffer, g_canvas_width, g_canvas_height);
}

void count_rect(int x0, int y0, int x1, int y1)
{
	if (x0 < 0) x0 = 0;
	if (y0 < 0) y0 = 0;
	if (x1 >= g_canvas_width) x1 = g_canvas_width - 1;
	if (y1 >= g_canvas_height) y1 = g_canvas_height - 1;
	if (x0 > x1 || y0 > y1) return;
	g_flush_rects++;
	g_flush_pixels += (x1 - x0 + 1) * (y1 - y0 + 1);
}

void copy_rect_to_presented(int x0, int y0, int x1, int y1)
{
	if (!g_framebuffer || !g_presented_framebuffer || g_canvas_width <= 0 || g_canvas_height <= 0) return;
	if (x0 < 0) x0 = 0;
	if (y0 < 0) y0 = 0;
	if (x1 >= g_canvas_width) x1 = g_canvas_width - 1;
	if (y1 >= g_canvas_height) y1 = g_canvas_height - 1;
	if (x0 > x1 || y0 > y1) return;

	const int width = x1 - x0 + 1;
	for (int y = y0; y <= y1; y++) {
		const std::size_t offset = static_cast<std::size_t>(y) * g_canvas_width + x0;
		std::copy_n(g_framebuffer + offset, width, g_presented_framebuffer + offset);
	}
}

}  // namespace

namespace gea::platform::display {

bool Display::init()
{
	ensure_canvas();
	return true;
}

bool Display::start() { return true; }

gea::framework::graphics::Canvas *Display::canvas()
{
	ensure_canvas();
	return &g_canvas;
}

void Display::clear() { canvas()->clear(0); }
void Display::clearNoFlush() { canvas()->clear(0); }
void Display::print(const char *) {}

// No double-buffered framebuffer on the iOS host shim — the canvas is the
// presented surface — so rebinding is a no-op (the embedded backends use this
// to re-point the canvas at a freshly-allocated framebuffer).
void Display::rebindCanvasToFramebuffer() {}

void Display::flush()
{
	ensure_canvas();
	g_flush_calls++;
	int x0 = 0;
	int y0 = 0;
	int x1 = -1;
	int y1 = -1;
	if (g_canvas.dirty(&x0, &y0, &x1, &y1)) {
		count_rect(x0, y0, x1, y1);
		copy_rect_to_presented(x0, y0, x1, y1);
	}
	g_canvas.resetDirty();
}

void Display::flushRects(const DisplayFlushRect *rects, int count, bool)
{
	ensure_canvas();
	if (!rects || count <= 0) return;
	g_flush_calls++;
	for (int i = 0; i < count; i++) {
		count_rect(rects[i].x0, rects[i].y0, rects[i].x1, rects[i].y1);
		copy_rect_to_presented(rects[i].x0, rects[i].y0, rects[i].x1, rects[i].y1);
	}
	g_canvas.resetDirty();
}

bool Display::streamRect(int x, int y, int w, int h, DisplayStreamRasterFn raster, void *user)
{
	ensure_canvas();
	if (!raster || w <= 0 || h <= 0) return false;
	int x0 = std::max(0, x);
	int y0 = std::max(0, y);
	int x1 = std::min(g_canvas_width - 1, x + w - 1);
	int y1 = std::min(g_canvas_height - 1, y + h - 1);
	if (x0 > x1 || y0 > y1) return true;

	const int rw = x1 - x0 + 1;
	const int rh = y1 - y0 + 1;
	// `DisplayStreamRasterFn` (display.h) is declared to fill `pixel::native_t`,
	// which on this target is the 32-bit RGBA8888 this file's own header states
	// -- so the raster already produces the framebuffer's format and there is
	// nothing to convert. The RGB565 scratch buffer and per-pixel
	// `rgba8888FromRgb565` this replaced were the un-migrated 16-bit path: they
	// declared the callback's output as half its actual width, which is why the
	// call did not compile at all.
	using native_t = gea::framework::graphics::pixel::native_t;
	std::vector<native_t> pixels(static_cast<std::size_t>(rw) * static_cast<std::size_t>(rh));
	raster(pixels.data(), rw, rh, x0, y0, user);
	for (int row = 0; row < rh; row++) {
		std::copy_n(&pixels[static_cast<std::size_t>(row) * static_cast<std::size_t>(rw)], rw,
		            &g_framebuffer[static_cast<std::size_t>((y0 + row) * g_canvas_width + x0)]);
	}
	g_canvas.markDirty(x0, y0, x1, y1);
	flush();
	return true;
}

bool Display::present(const DisplayPresentCommand *commands, int command_count)
{
	ensure_canvas();
	if (!commands || command_count <= 0) return false;
	for (int i = 0; i < command_count; i++) {
		const auto &command = commands[i];
		switch (command.type) {
			case DisplayPresentCommandType::Clear:
				g_canvas.clear(command.clear.color);
				break;
			case DisplayPresentCommandType::FillRectRgb565:
				g_canvas.setGlobalAlpha(command.fillRectRgb565.alpha);
				g_canvas.fillRect(command.fillRectRgb565.x, command.fillRectRgb565.y,
				                  command.fillRectRgb565.w, command.fillRectRgb565.h,
				                  command.fillRectRgb565.color);
				break;
			case DisplayPresentCommandType::StrokeRectRgb565:
				g_canvas.setGlobalAlpha(command.strokeRectRgb565.alpha);
				g_canvas.strokeRect(command.strokeRectRgb565.x, command.strokeRectRgb565.y,
				                    command.strokeRectRgb565.w, command.strokeRectRgb565.h,
				                    command.strokeRectRgb565.color);
				break;
			case DisplayPresentCommandType::FillTriangleRgb565:
				g_canvas.setGlobalAlpha(command.fillTriangleRgb565.alpha);
				g_canvas.fillTriangle(command.fillTriangleRgb565.x0, command.fillTriangleRgb565.y0,
				                      command.fillTriangleRgb565.x1, command.fillTriangleRgb565.y1,
				                      command.fillTriangleRgb565.x2, command.fillTriangleRgb565.y2,
				                      command.fillTriangleRgb565.color);
				break;
			case DisplayPresentCommandType::FillCircleRgb565:
				g_canvas.setGlobalAlpha(command.fillCircleRgb565.alpha);
				g_canvas.fillCircle(command.fillCircleRgb565.x, command.fillCircleRgb565.y,
				                    command.fillCircleRgb565.radius,
				                    command.fillCircleRgb565.color);
				break;
			case DisplayPresentCommandType::StrokeCircleRgb565:
				g_canvas.setGlobalAlpha(command.strokeCircleRgb565.alpha);
				g_canvas.strokeCircle(command.strokeCircleRgb565.x, command.strokeCircleRgb565.y,
				                      command.strokeCircleRgb565.radius,
				                      command.strokeCircleRgb565.color);
				break;
			case DisplayPresentCommandType::FillCirclesRgb565:
				g_canvas.setGlobalAlpha(command.fillCirclesRgb565.alpha);
				g_canvas.fillCirclesRgb565(command.fillCirclesRgb565.xs,
				                           command.fillCirclesRgb565.ys,
				                           command.fillCirclesRgb565.count,
				                           command.fillCirclesRgb565.radius,
				                           command.fillCirclesRgb565.colors);
				break;
			case DisplayPresentCommandType::DrawImage:
				g_canvas.setGlobalAlpha(command.drawImage.alpha);
				g_canvas.drawImage(command.drawImage.pixels, command.drawImage.alphaPixels,
				                   command.drawImage.srcWidth, command.drawImage.srcHeight,
				                   command.drawImage.x, command.drawImage.y);
				break;
			case DisplayPresentCommandType::DrawImageScaled:
				g_canvas.setGlobalAlpha(command.drawImageScaled.alpha);
				g_canvas.drawImage(command.drawImageScaled.pixels, command.drawImageScaled.alphaPixels,
				                   command.drawImageScaled.srcWidth, command.drawImageScaled.srcHeight,
				                   command.drawImageScaled.x, command.drawImageScaled.y,
				                   command.drawImageScaled.w, command.drawImageScaled.h);
				break;
			case DisplayPresentCommandType::DrawImageTiledX:
				g_canvas.setGlobalAlpha(command.drawImageTiledX.alpha);
				g_canvas.drawImageTiledX(command.drawImageTiledX.pixels, command.drawImageTiledX.alphaPixels,
				                         command.drawImageTiledX.srcWidth, command.drawImageTiledX.srcHeight,
				                         command.drawImageTiledX.x, command.drawImageTiledX.y,
				                         command.drawImageTiledX.w);
				break;
			case DisplayPresentCommandType::FillText:
				g_canvas.setGlobalAlpha(command.fillText.alpha);
				g_canvas.drawText(command.fillText.text, command.fillText.x, command.fillText.y,
				                  command.fillText.color, command.fillText.scale);
				break;
		}
	}
	g_canvas.setGlobalAlpha(255);
	flush();
	return true;
}

void Display::setFlushConfig(int chunk_rows, int queue_depth)
{
	g_flush_rows = chunk_rows;
	g_flush_depth = queue_depth;
}

int Display::flushChunkRows() { return g_flush_rows; }
int Display::flushQueueDepth() { return g_flush_depth; }
int Display::flushBufferBytes() { return g_canvas_width * g_flush_rows * 2 * g_flush_depth; }
void Display::pushClip(int x, int y, int w, int h) { canvas()->pushClip(x, y, w, h); }
void Display::popClip() { canvas()->popClip(); }
void Display::resetClip() { canvas()->resetClip(); }
void Display::setAlpha(std::uint8_t alpha) { g_alpha = alpha; canvas()->setGlobalAlpha(alpha); }
std::uint8_t Display::alpha() { return g_alpha; }
int Display::brightness() { return g_brightness; }
void Display::setBrightness(int brightness_percent)
{
	if (brightness_percent < 0) brightness_percent = 0;
	if (brightness_percent > 100) brightness_percent = 100;
	g_brightness = brightness_percent;
}
// Tearing sync (TE/VBlank): not implemented on this target.
void Display::setVSync(bool) {}
void Display::invalidate() {}
bool Display::vsyncEnabled() { return false; }
void Display::vsyncWaitForFrame() {}
void Display::clip(int *x0, int *y0, int *x1, int *y1) { canvas()->currentClip(x0, y0, x1, y1); }
void Display::fillRect(int x, int y, int w, int h, gea::framework::graphics::pixel::native_t color) { canvas()->fillRect(x, y, w, h, color); }
void Display::scrollRect(int x, int y, int w, int h, int dx, int dy) { canvas()->scrollRect(x, y, w, h, dx, dy); }
void Display::resetScrollRegion() { canvas()->setScrollRegion(0, 0, 0); }
void Display::strokeRect(int x, int y, int w, int h, gea::framework::graphics::pixel::native_t color) { canvas()->strokeRect(x, y, w, h, color); }
void Display::fillCircle(int cx, int cy, int r, gea::framework::graphics::pixel::native_t color) { canvas()->fillCircle(cx, cy, r, color); }
void Display::strokeCircle(int cx, int cy, int r, gea::framework::graphics::pixel::native_t color) { canvas()->strokeCircle(cx, cy, r, color); }
void Display::drawLine(int x0, int y0, int x1, int y1, gea::framework::graphics::pixel::native_t color) { canvas()->drawLine(x0, y0, x1, y1, color); }
void Display::drawArc(int cx, int cy, int r, int start_deg, int end_deg, gea::framework::graphics::pixel::native_t color) { canvas()->drawArc(cx, cy, r, start_deg, end_deg, color); }
void Display::fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, gea::framework::graphics::pixel::native_t color) { canvas()->fillTriangle(x0, y0, x1, y1, x2, y2, color); }
void Display::drawText(const char *text, int x, int y, gea::framework::graphics::pixel::native_t color, float scale) { canvas()->drawText(text, x, y, color, scale); }
void Display::drawTextFont(const char *text, int x, int y, gea::framework::graphics::pixel::native_t color, int font_id) { canvas()->drawTextFont(text, x, y, color, font_id); }
void Display::drawTextFontFamily(const char *text, int x, int y, gea::framework::graphics::pixel::native_t color, int family_id, int size_px)
{
	canvas()->drawTextFontFamily(text, x, y, color, family_id, size_px);
}
void Display::setPixel(int x, int y, gea::framework::graphics::pixel::native_t color) { canvas()->fillRect(x, y, 1, 1, color); }
void Display::fillRoundedRect(int x, int y, int w, int h, int tl, int tr, int br, int bl, gea::framework::graphics::pixel::native_t color) { canvas()->fillRoundedRect(x, y, w, h, tl, tr, br, bl, color); }
void Display::fillRoundedRectBoxesRgb565(const std::int16_t *xs, const std::int16_t *ys, int count,
                                         int w, int h, int tl, int tr, int br, int bl,
                                         const gea::framework::graphics::pixel::native_t *colors)
{
	canvas()->fillRoundedRectBoxesRgb565(xs, ys, count, w, h, tl, tr, br, bl, colors);
}
void Display::strokeRoundedRect(int x, int y, int w, int h, int tl, int tr, int br, int bl, int lw, gea::framework::graphics::pixel::native_t color) { canvas()->strokeRoundedRect(x, y, w, h, tl, tr, br, bl, lw, color); }
void Display::blitImage(const gea::framework::graphics::pixel::native_t *src, const std::uint8_t *alpha, int src_w, int src_h, int dx, int dy) { canvas()->drawImage(src, alpha, src_w, src_h, dx, dy); }
void Display::blitImageScaled(const gea::framework::graphics::pixel::native_t *src, const std::uint8_t *alpha, int src_w, int src_h, int dx, int dy, int dst_w, int dst_h) { canvas()->drawImage(src, alpha, src_w, src_h, dx, dy, dst_w, dst_h); }
void Display::setWorldOverlay(const std::uint16_t *, int, int, int, int) {}
void Display::setWorldScroll(int) {}
void Display::flushStatsRead(std::int64_t *total_us, int *call_count, int *pixel_count)
{
	if (total_us) *total_us = 0;
	if (call_count) *call_count = g_flush_calls;
	if (pixel_count) *pixel_count = g_flush_pixels;
}
DisplayFlushPerfStats Display::flushPerfStatsRead()
{
	DisplayFlushPerfStats stats;
	stats.callCount = g_flush_calls;
	stats.pixelCount = g_flush_pixels;
	return stats;
}
void Display::flushStatsReset()
{
	g_flush_calls = 0;
	g_flush_rects = 0;
	g_flush_pixels = 0;
}
const char *Display::flushStageName() { return "idle"; }
int Display::flushStageChunk() { return 0; }
DisplayFlushStageDetail Display::flushStageDetail() { return {}; }

// Orientation is a device-panel concept; the iOS app rotates via UIKit, not by
// rotating the framebuffer — so the framework rotation hook is a no-op here.
void applyOrientation(gea::framework::display::DisplayOrientation) {}

}  // namespace gea::platform::display

// Returns the presented RGBA8888 framebuffer (R,G,B,A bytes per pixel).
extern "C" const std::uint32_t *gea_ios_display_presented_pixels()
{
	ensure_canvas();
	return g_presented_framebuffer ? g_presented_framebuffer : g_framebuffer;
}

extern "C" void gea_ios_display_set_viewport_size(int width, int height)
{
	if (width <= 0 || height <= 0) return;
	g_canvas_width = width;
	g_canvas_height = height;
	ensure_canvas();
}

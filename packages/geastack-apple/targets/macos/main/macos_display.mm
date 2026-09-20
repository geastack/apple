#import <Cocoa/Cocoa.h>

#include "display.h"
#include "canvas.h"
#include "host/display_orientation.h"
#include "pixel.h"
#include "thermalright_hid_display.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

// The default macOS target renders Gea UI through AppKit-native NSViews, so
// Display::* stays inert there. Thermalright HID display builds flip this file
// back into the embedded-style RGB565 framebuffer path and stream full-canvas
// JPEG frames to the USB panel from flush/flushRects.

namespace {

gea::framework::graphics::Canvas g_canvas;
std::uint16_t *g_framebuffer = nullptr;
// Logical canvas size. Starts at the compile-time panel dims and follows the
// app's orientation: applyOrientation() below reallocates the surface (and
// resizes the window) to the rotated logical size, so window.innerWidth, the
// canvas surface, and the visible window always agree.
int g_canvas_w = gea::platform::display::kWidth;
int g_canvas_h = gea::platform::display::kHeight;
int g_brightness = 100;
std::uint8_t g_alpha = 255;
int g_flush_rows = 0;
int g_flush_depth = 0;
int g_flush_calls = 0;
int g_flush_pixels = 0;

void ensure_canvas()
{
	if (g_framebuffer) return;
	g_framebuffer = static_cast<std::uint16_t *>(std::calloc((size_t)g_canvas_w * (size_t)g_canvas_h, sizeof(std::uint16_t)));
	g_canvas.bindPixels(g_framebuffer, g_canvas_w, g_canvas_h);
}

bool framebuffer_target()
{
	return gea::macos::thermalright::enabled();
}

void count_rect(int x0, int y0, int x1, int y1)
{
	using gea::platform::display::kWidth;
	using gea::platform::display::kHeight;
	if (x0 < 0) x0 = 0;
	if (y0 < 0) y0 = 0;
	if (x1 >= kWidth) x1 = kWidth - 1;
	if (y1 >= kHeight) y1 = kHeight - 1;
	if (x0 > x1 || y0 > y1) return;
	g_flush_pixels += (x1 - x0 + 1) * (y1 - y0 + 1);
}

void submit_full_frame()
{
	if (!framebuffer_target()) return;
	ensure_canvas();
	gea::macos::thermalright::submitRgb565(g_framebuffer,
	                                       gea::platform::display::kWidth,
	                                       gea::platform::display::kHeight);
}

}  // namespace

namespace gea::platform::display {

bool Display::init() { ensure_canvas(); return true; }
bool Display::start() { return true; }

gea::framework::graphics::Canvas *Display::canvas()
{
	ensure_canvas();
	return &g_canvas;
}

void Display::clear()
{
	if (!framebuffer_target()) return;
	canvas()->clear(0);
	flush();
}

void Display::clearNoFlush()
{
	if (!framebuffer_target()) return;
	canvas()->clear(0);
}

void Display::print(const char *) {}
void Display::flush()
{
	if (!framebuffer_target()) return;
	ensure_canvas();
	g_flush_calls++;
	int x0 = 0;
	int y0 = 0;
	int x1 = -1;
	int y1 = -1;
	if (g_canvas.dirty(&x0, &y0, &x1, &y1)) count_rect(x0, y0, x1, y1);
	submit_full_frame();
	g_canvas.resetDirty();
}

void Display::flushRects(const DisplayFlushRect *rects, int count, bool)
{
	if (!framebuffer_target()) return;
	if (!rects || count <= 0) return;
	ensure_canvas();
	g_flush_calls++;
	for (int i = 0; i < count; i++) count_rect(rects[i].x0, rects[i].y0, rects[i].x1, rects[i].y1);
	submit_full_frame();
	g_canvas.resetDirty();
}

void Display::flushRectsRasterized(const DisplayFlushRect *rects, int count, DisplayStreamRasterFn raster, void *user, bool allowPerChunkDrain)
{
	(void)allowPerChunkDrain;
	if (!framebuffer_target() || !rects || count <= 0 || !raster) return;
	ensure_canvas();
	for (int i = 0; i < count; i++) {
		int x0 = std::max(0, rects[i].x0);
		int y0 = std::max(0, rects[i].y0);
		int x1 = std::min(kWidth - 1, rects[i].x1);
		int y1 = std::min(kHeight - 1, rects[i].y1);
		if (x0 > x1 || y0 > y1) continue;
		const int w = x1 - x0 + 1;
		const int h = y1 - y0 + 1;
		std::vector<std::uint16_t> pixels(static_cast<std::size_t>(w) * static_cast<std::size_t>(h));
		raster(pixels.data(), w, h, x0, y0, user);
		for (int row = 0; row < h; row++) {
			std::memcpy(g_framebuffer + static_cast<std::size_t>(y0 + row) * kWidth + x0,
			            pixels.data() + static_cast<std::size_t>(row) * w,
			            static_cast<std::size_t>(w) * sizeof(std::uint16_t));
		}
		g_canvas.markDirty(x0, y0, x1, y1);
	}
	flushRects(rects, count, allowPerChunkDrain);
}

void Display::rebindCanvasToFramebuffer()
{
	ensure_canvas();
	g_canvas.bindPixels(g_framebuffer, g_canvas_w, g_canvas_h);
}

bool Display::streamRect(int x, int y, int w, int h, DisplayStreamRasterFn raster, void *user)
{
	if (!framebuffer_target()) return false;
	ensure_canvas();
	if (!raster || w <= 0 || h <= 0) return false;
	int x0 = std::max(0, x);
	int y0 = std::max(0, y);
	int x1 = std::min(kWidth - 1, x + w - 1);
	int y1 = std::min(kHeight - 1, y + h - 1);
	if (x0 > x1 || y0 > y1) return true;

	const int rw = x1 - x0 + 1;
	const int rh = y1 - y0 + 1;
	std::vector<std::uint16_t> pixels(static_cast<std::size_t>(rw) * static_cast<std::size_t>(rh));
	raster(pixels.data(), rw, rh, x0, y0, user);
	for (int row = 0; row < rh; row++) {
		std::memcpy(g_framebuffer + static_cast<std::size_t>(y0 + row) * kWidth + x0,
		            pixels.data() + static_cast<std::size_t>(row) * rw,
		            static_cast<std::size_t>(rw) * sizeof(std::uint16_t));
	}
	g_canvas.markDirty(x0, y0, x1, y1);
	flush();
	return true;
}

bool Display::present(const DisplayPresentCommand *commands, int command_count)
{
	if (framebuffer_target()) {
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
				case DisplayPresentCommandType::FillTrianglesRgb565:
					// Entries are depth-ordered by the canvas layer; draw in order
					// (same replay as canvas_element's replayPresentBatchToCanvas).
					g_canvas.setGlobalAlpha(command.fillTrianglesRgb565.alpha);
					for (int t = 0; t < command.fillTrianglesRgb565.count; t++) {
						const auto &tri = command.fillTrianglesRgb565.entries[t];
						g_canvas.fillTriangle(tri.x0, tri.y0, tri.x1, tri.y1, tri.x2, tri.y2, tri.color);
					}
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
				case DisplayPresentCommandType::DrawImageRotated90CW:
					g_canvas.setGlobalAlpha(command.drawImageRotated90CW.alpha);
					g_canvas.drawImageRotated90CW(command.drawImageRotated90CW.pixels,
					                              command.drawImageRotated90CW.alphaPixels,
					                              command.drawImageRotated90CW.srcWidth,
					                              command.drawImageRotated90CW.srcHeight,
					                              command.drawImageRotated90CW.x,
					                              command.drawImageRotated90CW.y,
					                              command.drawImageRotated90CW.w,
					                              command.drawImageRotated90CW.h);
					break;
				case DisplayPresentCommandType::DrawImageTiledX:
					g_canvas.setGlobalAlpha(command.drawImageTiledX.alpha);
					g_canvas.drawImageTiledX(command.drawImageTiledX.pixels,
					                         command.drawImageTiledX.alphaPixels,
					                         command.drawImageTiledX.srcWidth,
					                         command.drawImageTiledX.srcHeight,
					                         command.drawImageTiledX.x,
					                         command.drawImageTiledX.y,
					                         command.drawImageTiledX.w);
					break;
				case DisplayPresentCommandType::FillText:
					g_canvas.setGlobalAlpha(command.fillText.alpha);
					if (command.fillText.fontFamilyId >= 0) {
						g_canvas.drawTextFontFamily(command.fillText.text,
						                            command.fillText.x,
						                            command.fillText.y,
						                            command.fillText.color,
						                            command.fillText.fontFamilyId,
						                            command.fillText.fontSizePx);
					} else {
						g_canvas.drawText(command.fillText.text,
						                  command.fillText.x,
						                  command.fillText.y,
						                  command.fillText.color,
						                  command.fillText.scale);
					}
					break;
			}
		}
		g_canvas.setGlobalAlpha(255);
		flush();
		return true;
	}
	// Return false to signal "the present pipeline can't run here". macOS
	// has no hardware-accelerated batched present (this is the ESP32 LCD
	// command path); if we return true the framework's CanvasRenderingContext2D
	// thinks the recorded fill/stroke commands were drawn and skips the
	// fallback that replays them onto the canvas surface — animations
	// freeze on frame 1 because the per-frame draws get silently dropped.
	// Returning false makes endBatch() take the replayPresentBatchToCanvas
	// path, so the canvas pixel buffer actually receives each frame.
	return false;
}

void Display::setFlushConfig(int chunk_rows, int queue_depth) { g_flush_rows = chunk_rows; g_flush_depth = queue_depth; }
int Display::flushChunkRows() { return g_flush_rows; }
int Display::flushQueueDepth() { return g_flush_depth; }
int Display::flushBufferBytes() { return kWidth * g_flush_rows * 2 * g_flush_depth; }

void Display::pushClip(int x, int y, int w, int h) { if (framebuffer_target()) canvas()->pushClip(x, y, w, h); }
void Display::popClip() { if (framebuffer_target()) canvas()->popClip(); }
void Display::resetClip() { if (framebuffer_target()) canvas()->resetClip(); }
void Display::setAlpha(uint8_t a)
{
	g_alpha = a;
	if (framebuffer_target()) canvas()->setGlobalAlpha(a);
}
uint8_t Display::alpha() { return g_alpha; }
int Display::brightness() { return g_brightness; }
void Display::setBrightness(int b)
{
	if (b < 0) b = 0;
	if (b > 100) b = 100;
	g_brightness = b;
}

// Tearing sync (TE/VBlank): not implemented on this target.
void Display::setVSync(bool) {}
void Display::invalidate() {}
bool Display::vsyncEnabled() { return false; }
void Display::vsyncWaitForFrame() {}

void Display::clip(int *x0, int *y0, int *x1, int *y1)
{
	if (x0) *x0 = 0;
	if (y0) *y0 = 0;
	if (x1) *x1 = g_canvas_w - 1;
	if (y1) *y1 = g_canvas_h - 1;
}

void Display::fillRect(int x, int y, int w, int h, uint16_t c) { if (framebuffer_target()) canvas()->fillRect(x, y, w, h, c); }
void Display::scrollRect(int x, int y, int w, int h, int dx, int dy) { if (framebuffer_target()) canvas()->scrollRect(x, y, w, h, dx, dy); }
void Display::resetScrollRegion() { if (framebuffer_target()) canvas()->setScrollRegion(0, 0, 0); }
void Display::strokeRect(int x, int y, int w, int h, uint16_t c) { if (framebuffer_target()) canvas()->strokeRect(x, y, w, h, c); }
void Display::fillCircle(int cx, int cy, int r, uint16_t c) { if (framebuffer_target()) canvas()->fillCircle(cx, cy, r, c); }
void Display::strokeCircle(int cx, int cy, int r, uint16_t c) { if (framebuffer_target()) canvas()->strokeCircle(cx, cy, r, c); }
void Display::drawLine(int x0, int y0, int x1, int y1, uint16_t c) { if (framebuffer_target()) canvas()->drawLine(x0, y0, x1, y1, c); }
void Display::drawArc(int cx, int cy, int r, int start_deg, int end_deg, uint16_t c) { if (framebuffer_target()) canvas()->drawArc(cx, cy, r, start_deg, end_deg, c); }
void Display::fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint16_t c) { if (framebuffer_target()) canvas()->fillTriangle(x0, y0, x1, y1, x2, y2, c); }
void Display::drawText(const char *text, int x, int y, uint16_t c, float scale) { if (framebuffer_target()) canvas()->drawText(text, x, y, c, scale); }
void Display::drawTextFont(const char *text, int x, int y, uint16_t c, int font_id)
{
	if (!framebuffer_target()) return;
#ifdef GEA_EMBEDDED_HAS_GENERATED_FONTS
	canvas()->drawTextFont(text, x, y, c, font_id);
#else
	(void)font_id;
	canvas()->drawText(text, x, y, c, 1.0f);
#endif
}
void Display::drawTextFontFamily(const char *text, int x, int y, uint16_t c, int family_id, int size_px) { if (framebuffer_target()) canvas()->drawTextFontFamily(text, x, y, c, family_id, size_px); }
void Display::setPixel(int x, int y, uint16_t c) { if (framebuffer_target()) canvas()->fillRect(x, y, 1, 1, c); }
void Display::fillRoundedRect(int x, int y, int w, int h, int tl, int tr, int br, int bl, uint16_t c) { if (framebuffer_target()) canvas()->fillRoundedRect(x, y, w, h, tl, tr, br, bl, c); }
void Display::fillRoundedRectBoxesRgb565(const int16_t *xs, const int16_t *ys, int count, int w, int h, int tl, int tr, int br, int bl, const uint16_t *colors)
{
	if (framebuffer_target()) canvas()->fillRoundedRectBoxesRgb565(xs, ys, count, w, h, tl, tr, br, bl, colors);
}
void Display::strokeRoundedRect(int x, int y, int w, int h, int tl, int tr, int br, int bl, int lw, uint16_t c) { if (framebuffer_target()) canvas()->strokeRoundedRect(x, y, w, h, tl, tr, br, bl, lw, c); }
void Display::blitImage(const gea::framework::graphics::pixel::native_t *src, const uint8_t *alpha, int src_w, int src_h, int dx, int dy) { if (framebuffer_target()) canvas()->drawImage(src, alpha, src_w, src_h, dx, dy); }
void Display::blitImageScaled(const gea::framework::graphics::pixel::native_t *src, const uint8_t *alpha, int src_w, int src_h, int dx, int dy, int dst_w, int dst_h) { if (framebuffer_target()) canvas()->drawImage(src, alpha, src_w, src_h, dx, dy, dst_w, dst_h); }
void Display::setWorldOverlay(const uint16_t *, int, int, int, int) {}
void Display::setWorldScroll(int) {}
bool Display::framebufferIsPanelDirect() { return false; }
bool Display::panelScanoutSurface(uint16_t **out_buffer, int *out_width, int *out_height)
{
	if (out_buffer) *out_buffer = nullptr;
	if (out_width) *out_width = 0;
	if (out_height) *out_height = 0;
	return false;
}
bool Display::panelDirectTarget(int, int, int, int, uint16_t **, int *, int *, int *, int *, int *, int *, int *, int *) { return false; }
void Display::flipPanelToBack() {}
bool Display::copySnapshotRgb565(uint16_t *dst, int pixel_capacity, int *width, int *height, bool)
{
	ensure_canvas();
	const int pixels = g_canvas_w * g_canvas_h;
	if (width) *width = g_canvas_w;
	if (height) *height = g_canvas_h;
	if (!dst || pixel_capacity < pixels) return false;
	std::memcpy(dst, g_framebuffer, static_cast<std::size_t>(pixels) * sizeof(std::uint16_t));
	return true;
}
int Display::countNonBlackPixels(bool)
{
	ensure_canvas();
	int count = 0;
	for (int i = 0; i < g_canvas_w * g_canvas_h; i++) {
		if (g_framebuffer[i] != 0) count++;
	}
	return count;
}
void Display::reserveInternal(std::size_t) {}
void Display::applyPendingInternalReserve() {}
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
void Display::presentPathDebug(int *calls, int *direct, int *general, int *rejected, int *tileShapeFailKind, int *tileShapeFailType, int *tileShapeFailCount)
{
	if (calls) *calls = 0;
	if (direct) *direct = 0;
	if (general) *general = 0;
	if (rejected) *rejected = 0;
	if (tileShapeFailKind) *tileShapeFailKind = 0;
	if (tileShapeFailType) *tileShapeFailType = 0;
	if (tileShapeFailCount) *tileShapeFailCount = 0;
}
void Display::landFrameDebug(int *total, int *align, int *raster, int *text, int *flip)
{
	if (total) *total = 0;
	if (align) *align = 0;
	if (raster) *raster = 0;
	if (text) *text = 0;
	if (flip) *flip = 0;
}
void Display::landPanDebug(int *detect, int *kick, int *strips, int *wait, int *interior)
{
	if (detect) *detect = 0;
	if (kick) *kick = 0;
	if (strips) *strips = 0;
	if (wait) *wait = 0;
	if (interior) *interior = 0;
}
void Display::flushStatsReset()
{
	g_flush_calls = 0;
	g_flush_pixels = 0;
}
const char *Display::flushStageName() { return "idle"; }
int Display::flushStageChunk() { return 0; }
DisplayFlushStageDetail Display::flushStageDetail() { return {}; }

// Rotation hook. Defining this (even as a no-op) advertises rotation support
// to DisplayOrientationState, which then flips the LOGICAL viewport on
// setOrientation('landscape') — so it must actually rotate: a no-op left the
// window, canvas surface, and AppKit layout at 410x502 while apps like maps
// sized their world to a 502x410 viewport that didn't exist (tiles right of
// x=410 fetched but never visible; the bottom 92px band never receiving the
// app's base fill, accumulating stale tile fragments on every pan). The Mac
// "panel" is a window, so rotating means resizing: reallocate the surface at
// the rotated logical size and match the window content to it.
void applyOrientation(gea::framework::display::DisplayOrientation)
{
	// The Thermalright HID panel has a fixed scanout — never resize it.
	if (framebuffer_target()) return;
	namespace od = gea::framework::display::detail;
	const int w = od::DisplayOrientationState::width();
	const int h = od::DisplayOrientationState::height();
	if (w <= 0 || h <= 0 || (w == g_canvas_w && h == g_canvas_h)) return;
	g_canvas_w = w;
	g_canvas_h = h;
	std::free(g_framebuffer);
	g_framebuffer = static_cast<std::uint16_t *>(std::calloc((size_t)w * (size_t)h, sizeof(std::uint16_t)));
	g_canvas.bindPixels(g_framebuffer, w, h);
	// Orientation is set from the app's top level inside Application::init,
	// which runs on the main thread with the window already on screen.
	NSWindow *window = NSApp.mainWindow ?: NSApp.windows.firstObject;
	if (window) {
		[window setContentSize:NSMakeSize(w, h)];
		[window center];
	}
}
bool autoRotateAllowed() { return false; }

}  // namespace gea::platform::display

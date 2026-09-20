#import "canvas_view.h"

#include "canvas.h"
#include "pixel.h"
#include "ui/tree_internal.h"

namespace {

std::uint8_t *g_scratch = nullptr;
std::size_t g_scratchBytes = 0;

std::uint8_t *ensureScratch(std::size_t bytes)
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

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_nodeId = -1;
		self.opaque = NO;
		self.backgroundColor = UIColor.clearColor;
		self.userInteractionEnabled = NO;
	}
	return self;
}

- (void)drawRect:(CGRect)dirtyRect
{
	(void)dirtyRect;
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;
	const auto *canvas = gea::embedded::ui::Tree::instance().canvas(self.nodeId);
	if (!canvas) return;
	const gea::framework::graphics::pixel::native_t *src = canvas->pixels();
	const int w = canvas->width();
	const int h = canvas->height();
	if (!src || w <= 0 || h <= 0) return;

	const std::size_t bytes = static_cast<std::size_t>(w) * h * 4;
	std::uint8_t *dst = ensureScratch(bytes);
	if (!dst) return;
#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
	// native_t is already RGBA8888 (R,G,B,A bytes per pixel) — exactly the
	// CGImage's RGBX layout — so present it straight through.
	std::memcpy(dst, src, bytes);
#else
	for (int i = 0; i < w * h; i++) {
		int r, g, b;
		gea::framework::graphics::pixel::unpackRgb565(src[i], &r, &g, &b);
		dst[i * 4 + 0] = static_cast<std::uint8_t>((r * 255 + 15) / 31);
		dst[i * 4 + 1] = static_cast<std::uint8_t>((g * 255 + 31) / 63);
		dst[i * 4 + 2] = static_cast<std::uint8_t>((b * 255 + 15) / 31);
		dst[i * 4 + 3] = 0xFF;
	}
#endif

	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, dst, bytes, nullptr);
	const uint32_t bitmapInfo = static_cast<uint32_t>(kCGImageAlphaNoneSkipLast) |
	                            static_cast<uint32_t>(kCGBitmapByteOrder32Big);
	CGImageRef image = CGImageCreate(static_cast<std::size_t>(w),
	                                 static_cast<std::size_t>(h),
	                                 8,
	                                 32,
	                                 static_cast<std::size_t>(w) * 4,
	                                 cs,
	                                 bitmapInfo,
	                                 provider,
	                                 nullptr,
	                                 false,
	                                 kCGRenderingIntentDefault);
	if (image) {
		UIImage *uiImage = [UIImage imageWithCGImage:image scale:1.0 orientation:UIImageOrientationUp];
		[uiImage drawInRect:self.bounds];
		CGImageRelease(image);
	}
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(cs);
}

@end

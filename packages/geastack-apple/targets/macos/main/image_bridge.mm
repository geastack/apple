#import <AppKit/AppKit.h>

#include "image_bridge.h"
#include "image.h"
#include "pixel.h"
#include "ui/tree_internal.h"
#include <cstdlib>
#include <algorithm>
#include <cmath>

namespace gea::macos {

NSImage *imageForNode(int nodeId)
{
 auto &tree = gea::embedded::ui::Tree::instance();
 if (nodeId < 0 || nodeId >= tree.nodeCount()) return nil;
 const auto &node = tree.node(nodeId);
 const char *width = tree.getAttribute(nodeId, "data-source-width");
 if (width && width[0]) {
   auto crop = [&](const char *name) { const char *value = tree.getAttribute(nodeId, name); return value ? std::atoi(value) : 0; };
   return imageForIdRegion(node.image_id, crop("data-source-x"), crop("data-source-y"), std::atoi(width), crop("data-source-height"));
 }
 if (node.style.image_fit == 2) return imageForIdCover(node.image_id, node.layout.width, node.layout.height);
 return imageForId(node.image_id);
}

NSImage *imageForId(int imageId)
{
 auto &store = gea::framework::graphics::ImageStore::instance();
 return imageForIdRegion(imageId, 0, 0, store.width(imageId), store.height(imageId));
}

NSImage *imageForIdCover(int imageId, int width, int height)
{
 auto &store = gea::framework::graphics::ImageStore::instance();
 const int sw = store.width(imageId), sh = store.height(imageId);
 if (width <= 0 || height <= 0 || sw <= 0 || sh <= 0) return nil;
 const double ratio = static_cast<double>(width) / height;
 int cw = sw, ch = sh;
 if (static_cast<double>(sw) / sh > ratio) cw = std::clamp(static_cast<int>(std::lround(sh * ratio)), 1, sw);
 else ch = std::clamp(static_cast<int>(std::lround(sw / ratio)), 1, sh);
 return imageForIdRegion(imageId, (sw - cw) / 2, (sh - ch) / 2, cw, ch);
}

NSImage *imageForIdRegion(int imageId, int x, int y, int w, int h)
{
	using namespace gea::framework::graphics;
	if (imageId < 0) return nil;
	auto &store = ImageStore::instance();
	const int sourceWidth = store.width(imageId);
 const int sourceHeight = store.height(imageId);
 if (x < 0 || y < 0 || w <= 0 || h <= 0 || x > sourceWidth - w || y > sourceHeight - h) return nil;
	const pixel::native_t *src = store.currentPixels(imageId);
	const std::uint8_t *alpha = store.currentAlpha(imageId);
	if (w <= 0 || h <= 0 || !src) return nil;

	const NSInteger pixelCount = w * h;
	NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)(pixelCount * 4)];
	std::uint8_t *dst = static_cast<std::uint8_t *>(rgba.mutableBytes);
	for (NSInteger i = 0; i < pixelCount; i++) {
		int r, g, b, a;
		const NSInteger sourceIndex = (y + i / w) * sourceWidth + x + i % w;
		pixel::unpackNative8(src[sourceIndex], &r, &g, &b, &a);
		dst[i * 4 + 0] = static_cast<std::uint8_t>(r);
		dst[i * 4 + 1] = static_cast<std::uint8_t>(g);
		dst[i * 4 + 2] = static_cast<std::uint8_t>(b);
		dst[i * 4 + 3] = alpha ? alpha[sourceIndex] : static_cast<std::uint8_t>(a);
	}

	NSBitmapImageRep *rep =
	    [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
	                                            pixelsWide:w
	                                            pixelsHigh:h
	                                         bitsPerSample:8
	                                       samplesPerPixel:4
	                                              hasAlpha:YES
	                                              isPlanar:NO
	                                        colorSpaceName:NSDeviceRGBColorSpace
	                                          bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
	                                           bytesPerRow:w * 4
	                                          bitsPerPixel:32];
	if (!rep) return nil;
	memcpy([rep bitmapData], dst, (size_t)(pixelCount * 4));

	NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
	[img addRepresentation:rep];
	return img;
}

}  // namespace gea::macos

#import <AppKit/AppKit.h>

#include "image_bridge.h"
#include "image.h"
#include "pixel.h"

namespace gea::macos {

NSImage *imageForId(int imageId)
{
	using namespace gea::framework::graphics;
	if (imageId < 0) return nil;
	auto &store = ImageStore::instance();
	const int w = store.width(imageId);
	const int h = store.height(imageId);
	const std::uint16_t *src = store.currentPixels(imageId);
	const std::uint8_t *alpha = store.currentAlpha(imageId);
	if (w <= 0 || h <= 0 || !src) return nil;

	const NSInteger pixelCount = w * h;
	NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)(pixelCount * 4)];
	std::uint8_t *dst = static_cast<std::uint8_t *>(rgba.mutableBytes);
	for (NSInteger i = 0; i < pixelCount; i++) {
		int r, g, b;
		pixel::unpackRgb565(src[i], &r, &g, &b);
		dst[i * 4 + 0] = static_cast<std::uint8_t>((r * 255 + 15) / 31);
		dst[i * 4 + 1] = static_cast<std::uint8_t>((g * 255 + 31) / 63);
		dst[i * 4 + 2] = static_cast<std::uint8_t>((b * 255 + 15) / 31);
		dst[i * 4 + 3] = alpha ? alpha[i] : 0xFF;
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

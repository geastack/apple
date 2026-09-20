#import <UIKit/UIKit.h>

#include "image_bridge.h"
#include "image.h"
#include "pixel.h"

#include <cstring>

namespace gea::ios {

UIImage *imageForId(int imageId)
{
	using namespace gea::framework::graphics;
	if (imageId < 0) return nil;
	auto &store = ImageStore::instance();
	const int w = store.width(imageId);
	const int h = store.height(imageId);
	if (w <= 0 || h <= 0) return nil;

	const std::size_t pixelCount = static_cast<std::size_t>(w) * h;
	NSMutableData *rgba = [NSMutableData dataWithLength:pixelCount * 4];
	std::uint8_t *dst = static_cast<std::uint8_t *>(rgba.mutableBytes);

	// On iOS pixel::native_t is RGBA8888 (bytes R,G,B,A in memory), so the store's
	// native pixels are already the full-colour source — a straight copy. This is
	// what makes PNG images and camera captures render at full colour, not 16-bit.
	const pixel::native_t *full = store.currentPixels(imageId);
	if (!full) return nil;
	std::memcpy(dst, full, pixelCount * sizeof(pixel::native_t));

	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
	const uint32_t bitmapInfo = static_cast<uint32_t>(kCGImageAlphaLast) |
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
	UIImage *result = image ? [UIImage imageWithCGImage:image scale:1.0 orientation:UIImageOrientationUp] : nil;
	if (image) CGImageRelease(image);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(cs);
	return result;
}

}  // namespace gea::ios

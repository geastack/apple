#import <AppKit/AppKit.h>

#include "color_convert.h"
#include "pixel.h"

namespace gea::macos {

namespace {

void unpack(gea::framework::graphics::pixel::native_t color, CGFloat *r, CGFloat *g, CGFloat *b)
{
	int ri, gi, bi, ai;
	gea::framework::graphics::pixel::unpackNative8(color, &ri, &gi, &bi, &ai);
	*r = static_cast<CGFloat>(ri) / 255.0;
	*g = static_cast<CGFloat>(gi) / 255.0;
	*b = static_cast<CGFloat>(bi) / 255.0;
}

}  // namespace

NSColor *nativeToNSColor(gea::framework::graphics::pixel::native_t color)
{
	CGFloat r, g, b;
	unpack(color, &r, &g, &b);
	return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

CGColor *nativeToCGColor(gea::framework::graphics::pixel::native_t color)
{
	CGFloat r, g, b;
	unpack(color, &r, &g, &b);
	CGFloat comps[4] = {r, g, b, 1.0};
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGColorRef result = CGColorCreate(cs, comps);
	CGColorSpaceRelease(cs);
	return result;
}

}  // namespace gea::macos

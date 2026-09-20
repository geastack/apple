#import <AppKit/AppKit.h>

#include "color_convert.h"
#include "pixel.h"

namespace gea::macos {

namespace {

void unpack(std::uint16_t rgb565, CGFloat *r, CGFloat *g, CGFloat *b)
{
	int ri, gi, bi;
	gea::framework::graphics::pixel::unpackRgb565(rgb565, &ri, &gi, &bi);
	*r = static_cast<CGFloat>(ri) / 31.0;
	*g = static_cast<CGFloat>(gi) / 63.0;
	*b = static_cast<CGFloat>(bi) / 31.0;
}

}  // namespace

NSColor *rgb565ToNSColor(std::uint16_t rgb565)
{
	CGFloat r, g, b;
	unpack(rgb565, &r, &g, &b);
	return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
}

CGColor *rgb565ToCGColor(std::uint16_t rgb565)
{
	CGFloat r, g, b;
	unpack(rgb565, &r, &g, &b);
	CGFloat comps[4] = {r, g, b, 1.0};
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGColorRef color = CGColorCreate(cs, comps);
	CGColorSpaceRelease(cs);
	return color;
}

}  // namespace gea::macos

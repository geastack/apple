#pragma once

#include "pixel.h"

#ifdef __OBJC__
@class NSColor;
#endif

namespace gea::macos {

#ifdef __OBJC__
NSColor *nativeToNSColor(gea::framework::graphics::pixel::native_t color);
#endif

// Caller-owns the returned CGColorRef; release with CGColorRelease.
struct CGColor *nativeToCGColor(gea::framework::graphics::pixel::native_t color);

}  // namespace gea::macos

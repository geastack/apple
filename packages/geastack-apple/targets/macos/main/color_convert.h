#pragma once

#include <cstdint>

#ifdef __OBJC__
@class NSColor;
#endif

namespace gea::macos {

#ifdef __OBJC__
NSColor *rgb565ToNSColor(std::uint16_t rgb565);
#endif

// Caller-owns the returned CGColorRef; release with CGColorRelease.
struct CGColor *rgb565ToCGColor(std::uint16_t rgb565);

}  // namespace gea::macos

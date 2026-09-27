#pragma once

#include <cstdint>

#ifdef __OBJC__
@class NSColor;
#endif

namespace gea::macos {

#ifdef __OBJC__
NSColor *rgb565ToNSColor(std::uint16_t rgb565);
// rgb565 carries no alpha; the style system keeps the CSS alpha beside it
// (text_alpha, bg_alpha, ...), 255 = opaque.
NSColor *rgb565ToNSColor(std::uint16_t rgb565, std::uint8_t alpha);
#endif

// Caller-owns the returned CGColorRef; release with CGColorRelease.
struct CGColor *rgb565ToCGColor(std::uint16_t rgb565);

}  // namespace gea::macos

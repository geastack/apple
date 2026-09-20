#pragma once

#ifdef __OBJC__
@class NSImage;
#endif

namespace gea::macos {

#ifdef __OBJC__
// Returns an NSImage built from the ImageStore slot at imageId, or nil if
// the slot is empty / invalid. Pixels are converted from RGB565 (+ optional
// alpha channel) to RGBA8888. Caller owns the result via ARC.
NSImage *imageForId(int imageId);
#endif

}  // namespace gea::macos

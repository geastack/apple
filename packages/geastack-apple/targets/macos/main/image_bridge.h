#pragma once

#ifdef __OBJC__
@class NSImage;
#endif

namespace gea::macos {

#ifdef __OBJC__
// Returns an NSImage built from the ImageStore slot at imageId, or nil if
// the slot is empty / invalid. Native color channels are preserved as RGBA8888.
// Caller owns the result via ARC.
NSImage *imageForId(int imageId);
NSImage *imageForNode(int nodeId);
NSImage *imageForIdRegion(int imageId, int x, int y, int width, int height);
NSImage *imageForIdCover(int imageId, int width, int height);
#endif

}  // namespace gea::macos

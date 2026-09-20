#pragma once

#include <cstdint>

#ifdef __OBJC__
#import <AppKit/AppKit.h>
@class NSFont;
@class NSString;
#endif

namespace gea::macos {

#ifdef __OBJC__
// Returns an NSFont for the given gea font id at the requested pixel size.
// fontId comes from the framework's lookupFontFamily which we override below
// to assign stable ids the first time each family is seen. Unknown ids fall
// back to the system font.
NSFont *fontForId(int fontId, int sizePx);

// Walks `directoryPath` for .ttf / .otf files and registers each with
// CTFontManager in the process scope. Returns the count of newly registered
// fonts; already-registered files are silently skipped. Call once at startup
// after the app bundle is known.
int registerCustomTtfDirectory(NSString *directoryPath);

// Picks the right NSLineBreakMode for `text` rendered in `font` within
// `maxWidth` points. Returns word-wrap when every space-separated chunk fits
// on a line by itself, otherwise char-wrap so that a long unbreakable run
// (like "TYPOGRAPHY") gets split mid-glyph instead of overflowing and being
// clipped at the field edge. Shared between the host measurement hook and
// the NSTextField renderer so both compute identical geometry.
NSLineBreakMode lineBreakModeForText(NSString *text, NSFont *font, CGFloat maxWidth);
#endif

}  // namespace gea::macos

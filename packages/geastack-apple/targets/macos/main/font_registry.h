#pragma once

#include <cstdint>

#ifdef __OBJC__
#import <AppKit/AppKit.h>
@class NSFont;
@class NSString;
#endif

namespace gea::macos {

#ifdef __OBJC__
// Returns an NSFont for the given gea font id at the requested pixel size and
// CSS font-weight (0 = unset = 400): the family's face nearest that weight.
// fontId comes from the framework's lookupFontFamily which we override below
// to assign stable ids the first time each family is seen. Unknown ids fall
// back to the system font.
NSFont *fontForId(int fontId, int sizePx, int weight = 400);

// NSStrokeWidthAttributeName that fakes a CSS bold (>= 600) the family has no
// face for — negative, so the outline is stroked AND filled, as a browser's
// synthetic bold is — or 0 when fontForId found a face heavy enough.
CGFloat syntheticBoldStrokeWidth(int fontId, int sizePx, int weight);

// Adds that stroke to `attrs` when there is one. Painting and measuring both go
// through it, so they see the same glyphs.
void addSyntheticBold(NSMutableDictionary *attrs, int fontId, int sizePx, int weight);

// NSTextFieldCell lays its text out this far in from each side of its frame
// (measured: 2pt at every size), even with the renderer's full-bounds drawing
// rect. The measurement hook reports the glyph run alone — what a browser's
// text box is — and the renderer widens each label by this much on both sides,
// so the run lands exactly on the box the engine allocated.
constexpr CGFloat kLabelSideInset = 2.0;

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

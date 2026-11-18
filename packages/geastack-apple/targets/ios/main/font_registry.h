#pragma once

#ifdef __OBJC__
#import <UIKit/UIKit.h>
@class UIFont;
#endif

namespace gea::ios {

#ifdef __OBJC__
// Returns a UIKit font for the generated framework font-family id. The id is
// resolved back to the CSS family name, then matched against fonts registered
// from the app bundle. Unknown ids fall back to the system font.
UIFont *fontForId(int fontId, CGFloat sizePt);
// Whether UIKit resolves `family` to a face of that family (not a fallback).
bool fontResolvesFamily(NSString *family, CGFloat size);
#endif
// Registers the app bundle's .ttf/.otf files with CoreText (once).
void ensureFontsRegistered();

}  // namespace gea::ios

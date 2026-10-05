#pragma once

#ifdef __OBJC__
#import <UIKit/UIKit.h>
@class UIFont;
#endif

namespace gea::ios {

#ifdef __OBJC__
// Returns a UIKit font for the generated framework font-family id at the CSS
// font-weight (0 = unset = 400): the family's face nearest that weight. The id
// is resolved back to the CSS family name, then matched against fonts
// registered from the app bundle. Unknown ids fall back to the system font.
UIFont *fontForId(int fontId, CGFloat sizePt, int weight = 400);

// NSStrokeWidthAttributeName that fakes a CSS bold (>= 600) the family has no
// face for — negative, so the outline is stroked AND filled, as a browser's
// synthetic bold is — or 0 when fontForId found a face heavy enough.
CGFloat syntheticBoldStrokeWidth(int fontId, CGFloat sizePt, int weight);

// Adds that stroke to `attrs` when there is one.
void addSyntheticBold(NSMutableDictionary *attrs, int fontId, CGFloat sizePt, int weight);
#endif

}  // namespace gea::ios

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
#endif

}  // namespace gea::ios

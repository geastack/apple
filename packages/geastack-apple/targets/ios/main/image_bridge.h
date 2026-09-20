#pragma once

#ifdef __OBJC__
@class UIImage;
#else
struct UIImage;
#endif

namespace gea::ios {

UIImage *imageForId(int imageId);

}  // namespace gea::ios

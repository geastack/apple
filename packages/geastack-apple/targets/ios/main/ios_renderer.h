#pragma once

#ifdef __OBJC__
@class UIView;
#else
struct UIView;
#endif

namespace gea::ios {

class IosRenderer {
public:
	static IosRenderer &instance();

	void sync(UIView *parentForRoot, int rootNodeId);
	void teardown();
	bool hasNativeTree() const;
};

}  // namespace gea::ios

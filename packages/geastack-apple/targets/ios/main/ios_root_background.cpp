#include "ios_root_background.h"

#include "ui/tree_internal.h"

namespace gea::ios {

bool mountedRootBackgroundColor(gea::framework::graphics::pixel::native_t *outColor)
{
	auto &tree = gea::embedded::ui::Tree::instance();
	const int root = tree.mountedRoot();
	if (root < 0 || root >= tree.nodeCount()) return false;

	const auto &style = tree.node(root).style;
	if (!style.has_bg) return false;

	if (outColor) *outColor = style.bg_color;
	return true;
}

}  // namespace gea::ios

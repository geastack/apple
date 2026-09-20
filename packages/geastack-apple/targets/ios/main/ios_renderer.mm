#include "ios_renderer.h"
#include "renderer/ios_renderer_internal.h"

namespace gea::ios {

IosRenderer &IosRenderer::instance()
{
	static IosRenderer renderer;
	return renderer;
}

void IosRenderer::sync(UIView *parentForRoot, int rootNodeId)
{
	renderer::syncNativeTree(parentForRoot, rootNodeId);
}

void IosRenderer::teardown()
{
	renderer::teardownNativeTree();
}

bool IosRenderer::hasNativeTree() const
{
	return renderer::hasNativeTree();
}

}  // namespace gea::ios

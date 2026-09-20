#include "ui/tree_internal.h"
#include "ui/tree_state.h"

#include <cstdint>
#include <cstdio>

namespace gea::ios {
bool mountedRootBackgroundColor(gea::framework::graphics::pixel::native_t *outColor);
}

namespace gea::framework::app::generated {
void drainMicrotasks() {}
}

namespace {

void resetTreeState()
{
	auto &state = gea::embedded::ui::treeState();
	for (int i = 0; i < state.nodeCount; i++) state.nodes[i] = gea::embedded::ui::Node{};
	state.nodeCount = 0;
	state.mountedRoot = -1;
	state.mountedWidth = 0;
	state.mountedHeight = 0;
}

bool expect(bool condition, const char *message)
{
	if (condition) return true;
	std::fprintf(stderr, "[test_ios_root_background] %s\n", message);
	return false;
}

}  // namespace

int main()
{
	auto &state = gea::embedded::ui::treeState();
	resetTreeState();

	gea::framework::graphics::pixel::native_t color = 0xffff;
	if (!expect(!gea::ios::mountedRootBackgroundColor(&color), "empty tree should not expose a root background")) return 1;

	resetTreeState();
	state.nodeCount = 1;
	state.mountedRoot = 0;
	state.nodes[0].style.has_bg = 1;
	state.nodes[0].style.bg_color = 0x1234;

	color = 0;
	if (!expect(gea::ios::mountedRootBackgroundColor(&color), "mounted root background should be present")) return 1;
	if (!expect(color == 0x1234, "mounted root background should match root node color")) return 1;

	state.nodeCount = 2;
	state.nodes[1].style.has_bg = 1;
	state.nodes[1].style.bg_color = 0x4321;

	color = 0;
	if (!expect(gea::ios::mountedRootBackgroundColor(&color), "mounted root background should remain present with children")) return 1;
	if (!expect(color == 0x1234, "child background should not override app background")) return 1;

	resetTreeState();
	state.nodeCount = 1;
	state.mountedRoot = 0;
	color = 0xabcd;
	if (!expect(!gea::ios::mountedRootBackgroundColor(&color), "root without background should not expose app background")) return 1;

	return 0;
}

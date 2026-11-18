// SPDX-License-Identifier: Apache-2.0
// The registry and life-cycle calls of iOS/tvOS host extensions (gea_uikit_host.h).
#include "gea_uikit_host.h"

#include <cstdio>

namespace {

constexpr int kMaxExtensions = 8;
const gea_uikit_host_extension *gExtensions[kMaxExtensions];
int gExtensionCount = 0;
// Extensions whose begin_frame ran this frame, so only they get end_frame.
bool gBegun[kMaxExtensions];

}  // namespace

extern "C" void gea_uikit_register_host_extension(const gea_uikit_host_extension *extension)
{
	if (!extension || extension->version != GEA_UIKIT_HOST_EXTENSION_VERSION) {
		std::fprintf(stderr, "[gea] host extension %s has an unsupported version\n", extension && extension->name ? extension->name : "?");
		return;
	}
	if (gExtensionCount >= kMaxExtensions) {
		std::fprintf(stderr, "[gea] too many host extensions; %s ignored\n", extension->name ? extension->name : "?");
		return;
	}
	gExtensions[gExtensionCount++] = extension;
}

extern "C" int gea_uikit_host_has_extensions(void) { return gExtensionCount > 0; }

extern "C" void gea_uikit_host_attach(void *rootView, double width, double height, double scale)
{
	for (int i = 0; i < gExtensionCount; ++i) {
		const auto *extension = gExtensions[i];
		if (extension->attach && !extension->attach(rootView, width, height, scale)) {
			std::fprintf(stderr, "[gea] host extension %s failed to attach\n", extension->name ? extension->name : "?");
		}
	}
}

extern "C" void gea_uikit_host_layout(double width, double height, double scale)
{
	for (int i = 0; i < gExtensionCount; ++i) {
		if (gExtensions[i]->layout) gExtensions[i]->layout(width, height, scale);
	}
}

extern "C" int gea_uikit_host_begin_frame(void)
{
	bool run = true;
	for (int i = 0; i < gExtensionCount; ++i) {
		gBegun[i] = false;
		if (!run) continue;
		if (gExtensions[i]->begin_frame && !gExtensions[i]->begin_frame()) {
			run = false;
			continue;
		}
		gBegun[i] = true;
	}
	if (!run) gea_uikit_host_end_frame();
	return run ? 1 : 0;
}

extern "C" void gea_uikit_host_end_frame(void)
{
	for (int i = gExtensionCount - 1; i >= 0; --i) {
		if (gBegun[i] && gExtensions[i]->end_frame) gExtensions[i]->end_frame();
		gBegun[i] = false;
	}
}

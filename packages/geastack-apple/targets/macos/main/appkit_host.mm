// SPDX-License-Identifier: Apache-2.0
// The registry and life-cycle calls of macOS host extensions (gea_appkit_host.h).
#include "gea_appkit_host.h"

#include <cstdio>

namespace {

constexpr int kMaxExtensions = 8;
const gea_appkit_host_extension *gExtensions[kMaxExtensions];
int gExtensionCount = 0;

}  // namespace

extern "C" void gea_appkit_register_host_extension(const gea_appkit_host_extension *extension)
{
	if (!extension || extension->version != GEA_APPKIT_HOST_EXTENSION_VERSION) {
		std::fprintf(stderr, "[gea] host extension %s has an unsupported version\n", extension && extension->name ? extension->name : "?");
		return;
	}
	if (gExtensionCount >= kMaxExtensions) {
		std::fprintf(stderr, "[gea] too many host extensions; %s ignored\n", extension->name ? extension->name : "?");
		return;
	}
	gExtensions[gExtensionCount++] = extension;
}

extern "C" void gea_appkit_host_attach(void *rootView, double width, double height, double scale)
{
	for (int i = 0; i < gExtensionCount; ++i) {
		const auto *extension = gExtensions[i];
		if (extension->attach && !extension->attach(rootView, width, height, scale)) {
			std::fprintf(stderr, "[gea] host extension %s failed to attach\n", extension->name ? extension->name : "?");
		}
	}
}

extern "C" void gea_appkit_host_layout(double width, double height, double scale)
{
	for (int i = 0; i < gExtensionCount; ++i) {
		if (gExtensions[i]->layout) gExtensions[i]->layout(width, height, scale);
	}
}

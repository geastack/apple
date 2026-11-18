// SPDX-License-Identifier: Apache-2.0
// Host extensions: native code a package (or an app) compiles into a macOS
// build to own part of the window -- typically a rendering surface such as a
// CAMetalLayer that a GL or GPU layer presents into, which the generated
// program draws through. The AppKit counterpart of gea_uikit_host.h, so a
// program that runs on tvOS runs unchanged on macOS.
//
// An extension registers itself from a static initializer:
//
//   static const gea_appkit_host_extension kSurface = {
//     GEA_APPKIT_HOST_EXTENSION_VERSION, "my-surface", attach, layout };
//   static const bool kRegistered = (gea_appkit_register_host_extension(&kSurface), true);
//
// Every callback may be null. Sizes are in points; `scale` is device pixels
// per point.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define GEA_APPKIT_HOST_EXTENSION_VERSION 1u

typedef struct gea_appkit_host_extension {
	unsigned version;  // GEA_APPKIT_HOST_EXTENSION_VERSION
	const char *name;  // for diagnostics
	// Once, after the window's root view exists and before the app's top level
	// runs. `rootView` is the root NSView (a bridged NSView *): an extension adds
	// its own subviews to it. Returning zero logs an error naming the extension.
	int (*attach)(void *rootView, double width, double height, double scale);
	// The root view's size or scale changed.
	void (*layout)(double width, double height, double scale);
} gea_appkit_host_extension;

void gea_appkit_register_host_extension(const gea_appkit_host_extension *extension);

// Called by the target (macos_main.mm).
void gea_appkit_host_attach(void *rootView, double width, double height, double scale);
void gea_appkit_host_layout(double width, double height, double scale);

#ifdef __cplusplus
}
#endif

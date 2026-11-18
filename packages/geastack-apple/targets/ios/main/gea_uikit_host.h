// SPDX-License-Identifier: Apache-2.0
// Host extensions: native code a package (or an app) compiles into an iOS or
// tvOS build to own part of the window -- typically a rendering surface such as
// a CAMetalLayer that a GL or GPU layer presents into, which the generated
// program draws through. The UIKit counterpart of gea_win32_host.h.
//
// The target calls every registered extension at fixed points of its life
// cycle; an extension registers itself from a static initializer:
//
//   static const gea_uikit_host_extension kSurface = {
//     GEA_UIKIT_HOST_EXTENSION_VERSION, "my-surface", attach, layout, begin, end, detach };
//   static const bool kRegistered = (gea_uikit_register_host_extension(&kSurface), true);
//
// Every callback may be null. Sizes are in points (layout pixels); `scale` is
// device pixels per point.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define GEA_UIKIT_HOST_EXTENSION_VERSION 1u

typedef struct gea_uikit_host_extension {
	unsigned version;  // GEA_UIKIT_HOST_EXTENSION_VERSION
	const char *name;  // for diagnostics
	// Once, after the window's root view exists and before the app's top level
	// runs. `rootView` is the root UIView (a bridged UIView *): an extension adds
	// its own subviews to it. Returning zero logs an error naming the extension.
	int (*attach)(void *rootView, double width, double height, double scale);
	// The root view's size or scale changed.
	void (*layout)(double width, double height, double scale);
	// Around the app's initialization and around every frame. A zero return
	// from begin_frame skips that frame; end_frame runs whenever begin_frame ran.
	int (*begin_frame)(void);
	void (*end_frame)(void);
	// Never called today (an iOS app is not shut down); for symmetry with Windows.
	void (*detach)(void);
} gea_uikit_host_extension;

void gea_uikit_register_host_extension(const gea_uikit_host_extension *extension);

// Called by the target (ios_main.mm).
void gea_uikit_host_attach(void *rootView, double width, double height, double scale);
void gea_uikit_host_layout(double width, double height, double scale);
// Returns zero when an extension skipped the frame; gea_uikit_host_end_frame
// must follow a nonzero return.
int gea_uikit_host_begin_frame(void);
void gea_uikit_host_end_frame(void);
// Whether any extension is registered (the host then leaves the window to it).
int gea_uikit_host_has_extensions(void);

#ifdef __cplusplus
}
#endif

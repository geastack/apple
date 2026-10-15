#ifndef GEA_WATCHOS_BRIDGE_H
#define GEA_WATCHOS_BRIDGE_H

// The C surface the SwiftUI shell (watchos_app.swift) drives the gea runtime
// through. It is the Swift bridging header, so it stays plain C: Swift imports
// it through clang as Objective-C, never as C++.

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

// Phases for gea_watchos_touch.
typedef enum {
	GeaWatchTouchDown = 0,
	GeaWatchTouchMove = 1,
	GeaWatchTouchUp = 2,
} GeaWatchTouchPhase;

// Mounts the app on a canvas of widthPx x heightPx physical pixels. `scale` is
// the screen's pixels-per-point, used to map touches from view points.
// Only the first call mounts; later ones are ignored.
void gea_watchos_start(int widthPx, int heightPx, double scale);

// Runs one gea frame (microtasks, rAF callbacks, style, layout, paint).
// Returns 1 when the presented framebuffer changed since the previous call.
int gea_watchos_frame(void);

// A snapshot of the presented framebuffer, or NULL before the first frame.
CGImageRef _Nullable gea_watchos_copy_frame_image(void) CF_RETURNS_RETAINED;

// Feeds a touch in view points (origin top-left of the canvas view).
void gea_watchos_touch(GeaWatchTouchPhase phase, double xPoints, double yPoints);

// Feeds a Digital Crown rotation of deltaPoints view points (positive = toward
// the end of the content). Scrolls the first vertical scroll container.
void gea_watchos_crown(double deltaPoints);

// The offset and range, in view points, of the container the Crown scrolls.
// Returns 0 when nothing scrolls vertically.
int gea_watchos_scroll_metrics(double *_Nonnull topPoints, double *_Nonnull maxPoints);

#ifdef __cplusplus
}
#endif

#endif

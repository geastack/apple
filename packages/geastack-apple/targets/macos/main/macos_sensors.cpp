#include "imu.h"
#include "memory.h"
#include "power.h"
#include "touch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>

#include <cstdint>

// macOS doesn't have an IMU; stubs let host/imu.cpp link. Tilt is fixed at 0.
namespace gea::platform::sensors {

void Accelerometer::init() {}
void Accelerometer::close() {}
void Accelerometer::calibrateBias() {}
int Accelerometer::tiltX() { return 0; }
int Accelerometer::tiltY() { return 0; }
double Accelerometer::accelerationX() { return 0.0; }
double Accelerometer::accelerationY() { return 0.0; }
double Accelerometer::accelerationZ() { return 9.80665; }  // gravity, plate flat
double Accelerometer::gyroscopeX() { return 0.0; }
double Accelerometer::gyroscopeY() { return 0.0; }
double Accelerometer::gyroscopeZ() { return 0.0; }
void Accelerometer::setWebTilt(int, int) {}

}  // namespace gea::platform::sensors

// Memory diagnostics — stub everything to zeros. macOS has plenty of RAM
// and the diagnostics views just show "0" for the embedded-only metrics.
namespace gea::platform::memory {

std::uint32_t Memory::internalFree() { return 0; }
std::uint32_t Memory::internalLargestFreeBlock() { return 0; }
std::uint32_t Memory::internalMinimumFree() { return 0; }
std::uint32_t Memory::psramFree() { return 0; }
std::uint32_t Memory::currentTaskStackHighWaterMark() { return 0; }
std::uint32_t Memory::geaMainStackBytes() { return 0; }
std::uint32_t Memory::geaInitStackBytes() { return 0; }
std::uint32_t Memory::appFrameStackWords() { return 0; }
std::uint32_t Memory::appFrameStackBytes() { return 0; }
std::uint32_t Memory::displayFlushConfiguredRows() { return 0; }
std::uint32_t Memory::displayFlushConfiguredDepth() { return 0; }
std::uint32_t Memory::displayFlushBufferMaxBytes() { return 0; }
std::uint32_t Memory::displayFlushRows() { return 0; }
std::uint32_t Memory::displayFlushDepth() { return 0; }
std::uint32_t Memory::displayFlushBufferBytes() { return 0; }

// No internal/external split here, so there is nothing to hold back for the
// display; the caller treats nullptr as "no reserve" and carries on.
void *Memory::reserveInternalDma(std::size_t) { return nullptr; }
void Memory::releaseInternalDma(void *) {}
}  // namespace gea::platform::memory

// Touch is driven by AppKit mouse events (GeaCanvasView dispatches them as
// touch events, mirroring the iOS renderer's gea_ios_touch_set_state flow).
// The mouse handler keeps this cache current so the frame loop's Move
// dispatch — which re-reads coordinates via consumeLatestMove — and
// immediate-mode apps polling read()/readCached() see the real pointer.
// Coordinates are PANEL-NATIVE, matching the hardware touch controllers
// (TouchRuntime::transformTouchToLogical maps them back to logical space).
namespace gea::platform::touch {

namespace {
bool g_touching = false;
int g_touch_x = 0;
int g_touch_y = 0;
}  // namespace

extern "C" void gea_macos_touch_set_state(int touching, int x, int y)
{
	g_touching = touching != 0;
	g_touch_x = x;
	g_touch_y = y;
}

void Touchscreen::setObserver(Observer) {}
bool Touchscreen::init() { return true; }
int Touchscreen::read(int *x, int *y)
{
	if (x) *x = g_touch_x;
	if (y) *y = g_touch_y;
	return g_touching ? 1 : 0;
}
int Touchscreen::readCached(int *x, int *y)
{
	if (x) *x = g_touch_x;
	if (y) *y = g_touch_y;
	return g_touching ? 1 : 0;
}
void Touchscreen::consumeLatestMove(int *x, int *y)
{
	if (x) *x = g_touch_x;
	if (y) *y = g_touch_y;
}

}  // namespace gea::platform::touch

// Battery. `gea::platform::power::Power` had no macOS implementation at all,
// so `host/battery.h`'s inline `batteryPercent()` left an undefined symbol and
// every app that shows a battery level failed to LINK (`watch`, `watch-date`:
// "gea::platform::power::Power::batteryPercent()", referenced from ...).
//
// A stub returning a constant would link and lie. macOS publishes the real
// figure through IOKit's power-sources API, and the target already links
// -framework IOKit (targets/macos/build-macos.sh LINK_FRAMEWORKS), so the
// honest implementation costs nothing the build was not already paying.
// A desktop with no battery reports 100: "not running on battery" is the
// truthful answer there, and it is what the embedded API's callers expect
// when the device is on external power.
namespace gea::platform::power {

bool Power::init() { return true; }

int Power::batteryPercent()
{
	CFTypeRef blob = IOPSCopyPowerSourcesInfo();
	if (blob == nullptr) return 100;
	CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
	if (sources == nullptr) {
		CFRelease(blob);
		return 100;
	}
	int percent = 100;
	const CFIndex count = CFArrayGetCount(sources);
	for (CFIndex i = 0; i < count; ++i) {
		CFDictionaryRef description = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(sources, i));
		if (description == nullptr) continue;
		CFNumberRef current = static_cast<CFNumberRef>(CFDictionaryGetValue(description, CFSTR(kIOPSCurrentCapacityKey)));
		CFNumberRef maximum = static_cast<CFNumberRef>(CFDictionaryGetValue(description, CFSTR(kIOPSMaxCapacityKey)));
		int currentValue = 0;
		int maximumValue = 0;
		if (current == nullptr || maximum == nullptr) continue;
		if (!CFNumberGetValue(current, kCFNumberIntType, &currentValue)) continue;
		if (!CFNumberGetValue(maximum, kCFNumberIntType, &maximumValue)) continue;
		if (maximumValue <= 0) continue;
		percent = static_cast<int>((static_cast<double>(currentValue) / maximumValue) * 100.0 + 0.5);
		break;
	}
	CFRelease(sources);
	CFRelease(blob);
	if (percent < 0) return 0;
	if (percent > 100) return 100;
	return percent;
}

}  // namespace gea::platform::power

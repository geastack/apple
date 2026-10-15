#import <WatchKit/WatchKit.h>

#include "camera.h"
#include "power.h"

#include <cmath>
#include <string>

// Platform services iOS has and the watch either lacks or provides
// differently: there is no camera, and battery and haptics come from WatchKit.

namespace gea::platform::camera {

// A watch has no camera. The host bridge (host/camera.cpp) still links, so apps
// that use one build and simply see `isAvailable() == false`, the same as a
// board without a sensor; a <camera> element renders nothing.
bool Camera::isAvailable() { return false; }
bool Camera::hasPermission() { return false; }
bool Camera::requestPermission() { return false; }
bool Camera::open(const std::string &, int, int) { return false; }
void Camera::close() {}
bool Camera::isOpen() { return false; }
int Camera::width() { return 0; }
int Camera::height() { return 0; }
int Camera::orientation() { return 0; }
Facing Camera::currentFacing() { return Facing::Back; }
std::string Camera::currentFacingString() { return "back"; }
int Camera::deviceCount() { return 0; }
DeviceInfo Camera::deviceAt(int) { return {}; }
void Camera::drawPreview(int, int, int, int) {}
int Camera::previewMode() { return 0; }
bool Camera::fillPreview(gea::framework::graphics::pixel::native_t *, int, int, int, bool) { return false; }
void Camera::positionPreviewLayer(int, int, int, int) {}
void Camera::hidePreviewLayer() {}
void Camera::presentNativeOverlay() {}
int Camera::capture(bool) { return -1; }
bool Camera::startRecording(const std::string &, double) { return false; }
double Camera::stopRecording() { return -1.0; }
bool Camera::isRecording() { return false; }
void Camera::setFlash(const std::string &) {}
void Camera::setZoom(double) {}
void Camera::setMirror(bool) {}
void Camera::setExposure(const std::string &, double, double, double) {}
void Camera::setWhiteBalance(const std::string &, double, double) {}
void Camera::setFocus(const std::string &, double, double) {}
void Camera::setTorch(const std::string &, double) {}

}  // namespace gea::platform::camera

namespace gea::platform::power {

namespace {

WKInterfaceDevice *device()
{
	WKInterfaceDevice *current = WKInterfaceDevice.currentDevice;
	if (!current.batteryMonitoringEnabled) current.batteryMonitoringEnabled = YES;
	return current;
}

}  // namespace

bool Power::init()
{
	device();
	return true;
}

// WatchKit reports 0..1, or a negative level when it cannot tell (the
// simulator); report a full battery then rather than an alarming 0%.
int Power::batteryPercent()
{
	const float level = device().batteryLevel;
	if (level < 0) return 100;
	return static_cast<int>(std::lround(level * 100.0f));
}

bool Power::charging()
{
	const WKInterfaceDeviceBatteryState state = device().batteryState;
	return state == WKInterfaceDeviceBatteryStateCharging || state == WKInterfaceDeviceBatteryStateFull;
}

// The Taptic Engine plays fixed patterns rather than a duration and strength,
// so a vibration maps to its closest one: a light click for a short buzz, the
// stronger notification pattern otherwise.
bool Power::vibrate(double durationMs, int strength)
{
	if (durationMs <= 0) return false;
	const WKHapticType haptic = (durationMs < 60 && strength < 50) ? WKHapticTypeClick : WKHapticTypeNotification;
	[device() playHaptic:haptic];
	return true;
}

}  // namespace gea::platform::power

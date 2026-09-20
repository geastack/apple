#include "imu.h"
#include "touch.h"

#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>

namespace gea::platform::sensors {

namespace {

constexpr NSTimeInterval kMotionUpdateInterval = 1.0 / 60.0;
constexpr double kPi = 3.14159265358979323846;
constexpr double kRadiansToDegrees = 180.0 / kPi;
constexpr double kStandardGravity = 9.80665;

double g_gyro_bias_x = 0.0;
double g_gyro_bias_y = 0.0;
double g_gyro_bias_z = 0.0;

struct Acceleration {
	double x = 0.0;
	double y = 0.0;
	double z = 1.0;
};

struct RotationRate {
	double x = 0.0;
	double y = 0.0;
	double z = 0.0;
};

Acceleration mapCoreMotionAccelerationToGea(Acceleration raw)
{
	return { raw.y, -raw.x, raw.z };
}

RotationRate mapCoreMotionRotationRateToGea(RotationRate raw)
{
	return { raw.y, -raw.x, raw.z };
}

CMMotionManager *motionManager()
{
	static CMMotionManager *manager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		manager = [[CMMotionManager alloc] init];
	});
	return manager;
}

void startMotionUpdates()
{
	CMMotionManager *manager = motionManager();
	if (manager.deviceMotionAvailable) {
		manager.deviceMotionUpdateInterval = kMotionUpdateInterval;
		if (!manager.deviceMotionActive) {
			[manager startDeviceMotionUpdates];
		}
		return;
	}

	if (manager.accelerometerAvailable && !manager.accelerometerActive) {
		manager.accelerometerUpdateInterval = kMotionUpdateInterval;
		[manager startAccelerometerUpdates];
	}
	if (manager.gyroAvailable && !manager.gyroActive) {
		manager.gyroUpdateInterval = kMotionUpdateInterval;
		[manager startGyroUpdates];
	}
}

Acceleration currentAcceleration()
{
	startMotionUpdates();

	CMMotionManager *manager = motionManager();
	CMDeviceMotion *motion = manager.deviceMotion;
	if (motion) {
		CMAcceleration gravity = motion.gravity;
		CMAcceleration userAcceleration = motion.userAcceleration;
		return mapCoreMotionAccelerationToGea({
			(gravity.x + userAcceleration.x) * kStandardGravity,
			(gravity.y + userAcceleration.y) * kStandardGravity,
			(gravity.z + userAcceleration.z) * kStandardGravity,
		});
	}

	CMAccelerometerData *data = manager.accelerometerData;
	if (data) {
		CMAcceleration acceleration = data.acceleration;
		return mapCoreMotionAccelerationToGea({
			acceleration.x * kStandardGravity,
			acceleration.y * kStandardGravity,
			acceleration.z * kStandardGravity,
		});
	}

	return {};
}

RotationRate currentRotationRate()
{
	startMotionUpdates();

	CMMotionManager *manager = motionManager();
	CMDeviceMotion *motion = manager.deviceMotion;
	if (motion) {
		CMRotationRate rate = motion.rotationRate;
		return mapCoreMotionRotationRateToGea({
			rate.x * kRadiansToDegrees,
			rate.y * kRadiansToDegrees,
			rate.z * kRadiansToDegrees,
		});
	}

	CMGyroData *data = manager.gyroData;
	if (data) {
		CMRotationRate rate = data.rotationRate;
		return mapCoreMotionRotationRateToGea({
			rate.x * kRadiansToDegrees,
			rate.y * kRadiansToDegrees,
			rate.z * kRadiansToDegrees,
		});
	}

	return {};
}

int tiltFromAxis(double axisMetersPerSecondSquared)
{
	const double axisG = axisMetersPerSecondSquared / kStandardGravity;
	const int value = static_cast<int>(axisG * 70.0);
	return std::clamp(value, -100, 100);
}

}  // namespace

void Accelerometer::init()
{
	startMotionUpdates();
}

void Accelerometer::close()
{
	CMMotionManager *manager = motionManager();
	if (manager.deviceMotionActive) [manager stopDeviceMotionUpdates];
	if (manager.accelerometerActive) [manager stopAccelerometerUpdates];
	if (manager.gyroActive) [manager stopGyroUpdates];
}

void Accelerometer::calibrateBias()
{
	RotationRate rate = currentRotationRate();
	g_gyro_bias_x = rate.x;
	g_gyro_bias_y = rate.y;
	g_gyro_bias_z = rate.z;
}

int Accelerometer::tiltX()
{
	return tiltFromAxis(currentAcceleration().y);
}

int Accelerometer::tiltY()
{
	return tiltFromAxis(-currentAcceleration().x);
}

double Accelerometer::accelerationX()
{
	return currentAcceleration().x;
}

double Accelerometer::accelerationY()
{
	return currentAcceleration().y;
}

double Accelerometer::accelerationZ()
{
	return currentAcceleration().z;
}

double Accelerometer::gyroscopeX()
{
	return currentRotationRate().x - g_gyro_bias_x;
}

double Accelerometer::gyroscopeY()
{
	return currentRotationRate().y - g_gyro_bias_y;
}

double Accelerometer::gyroscopeZ()
{
	return currentRotationRate().z - g_gyro_bias_z;
}

void Accelerometer::setWebTilt(int, int) {}

}  // namespace gea::platform::sensors

namespace gea::platform::touch {

namespace {
bool g_touching = false;
int g_touch_x = 0;
int g_touch_y = 0;
}  // namespace

extern "C" void gea_ios_touch_set_state(int touching, int x, int y)
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

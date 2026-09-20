// iOS implementation of the cross-platform gea::platform::camera::Camera backend.
//
// Preview uses the NativeOverlay model: an AVCaptureVideoPreviewLayer is added
// as a sublayer of the on-screen gea framebuffer view (gea_ios_camera_host_view)
// and positioned to the <camera> node's computed rect each frame by the runtime
// (CameraRenderer -> positionPreviewLayer). A parallel AVCaptureVideoDataOutput
// keeps the latest frame so capture() can return a still synchronously, matching
// the other platforms. Video recording is deferred (startRecording returns false).
//
// This does NOT touch the existing direct-AVFoundation path used by
// examples/apps/ios-device-showcase — it's an additive backend so the unified
// <camera> element / Camera facade work on iOS too.

#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

#include "camera.h"
#include "canvas.h"
#include "display.h"
#include "image.h"
#include "pixel.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace pixel = gea::framework::graphics::pixel;

// Exposed by ios_main.mm — the UIView hosting the gea framebuffer on screen.
extern "C" UIView *gea_ios_camera_host_view(void);

// Receives video frames so capture() can grab the most recent one synchronously.
@interface GeaCameraFrameSink : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

namespace gea::platform::camera {

namespace {

struct IosCameraState {
	AVCaptureSession *session = nil;
	AVCaptureDevice *device = nil;
	AVCaptureDeviceInput *input = nil;
	AVCaptureVideoDataOutput *dataOutput = nil;
	AVCaptureVideoPreviewLayer *previewLayer = nil;
	GeaCameraFrameSink *frameSink = nil;
	dispatch_queue_t sampleQueue = nullptr;

	bool open = false;
	bool mirror = false;
	int width = 0;
	int height = 0;
	Facing facing = Facing::Back;

	// Latest frame as full-colour RGBA8888 (bytes R,G,B,A), guarded for
	// synchronous capture().
	std::mutex frameMutex;
	std::vector<std::uint32_t> latestFrame;
	int latestWidth = 0;
	int latestHeight = 0;
};

IosCameraState &state()
{
	static IosCameraState s;
	return s;
}

AVCaptureDevicePosition positionForHint(const std::string &hint, Facing &facingOut)
{
	if (hint == "front") {
		facingOut = Facing::Front;
		return AVCaptureDevicePositionFront;
	}
	facingOut = Facing::Back;
	return AVCaptureDevicePositionBack;
}

void storeLatestFrame(CVImageBufferRef imageBuffer)
{
	if (!imageBuffer) return;
	CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
	const int w = static_cast<int>(CVPixelBufferGetWidth(imageBuffer));
	const int h = static_cast<int>(CVPixelBufferGetHeight(imageBuffer));
	const std::uint8_t *base = static_cast<const std::uint8_t *>(CVPixelBufferGetBaseAddress(imageBuffer));
	const std::size_t stride = CVPixelBufferGetBytesPerRow(imageBuffer);
	if (base && w > 0 && h > 0) {
		auto &s = state();
		std::lock_guard<std::mutex> lock(s.frameMutex);
		s.latestFrame.resize(static_cast<std::size_t>(w) * h);
		s.latestWidth = w;
		s.latestHeight = h;
		// AVCaptureVideoDataOutput is configured for 32BGRA (bytes B,G,R,A);
		// pack to full-colour RGBA8888 (bytes R,G,B,A) — no 565 quantization.
		for (int y = 0; y < h; ++y) {
			const std::uint8_t *srcRow = base + static_cast<std::size_t>(y) * stride;
			std::uint32_t *dstRow = s.latestFrame.data() + static_cast<std::size_t>(y) * w;
			for (int x = 0; x < w; ++x) {
				const std::uint8_t *p = srcRow + static_cast<std::size_t>(x) * 4;
				dstRow[x] = pixel::packRgba8888(p[2], p[1], p[0], 255);  // B,G,R,A -> R,G,B,A
			}
		}
		s.width = w;
		s.height = h;
	}
	CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

CGRect canvasRectToViewPoints(UIView *host, int x, int y, int w, int h)
{
	auto *canvas = gea::platform::display::Display::canvas();
	const CGRect bounds = host.bounds;
	if (!canvas || canvas->width() <= 0 || canvas->height() <= 0) return bounds;
	const CGFloat scale = std::min(bounds.size.width / static_cast<CGFloat>(canvas->width()),
	                               bounds.size.height / static_cast<CGFloat>(canvas->height()));
	const CGFloat destW = static_cast<CGFloat>(canvas->width()) * scale;
	const CGFloat destH = static_cast<CGFloat>(canvas->height()) * scale;
	const CGFloat originX = bounds.origin.x + (bounds.size.width - destW) * 0.5;
	const CGFloat originY = bounds.origin.y + (bounds.size.height - destH) * 0.5;
	return CGRectMake(originX + static_cast<CGFloat>(x) * scale,
	                  originY + static_cast<CGFloat>(y) * scale,
	                  static_cast<CGFloat>(w) * scale,
	                  static_cast<CGFloat>(h) * scale);
}

bool withLockedConfig(void (^body)(AVCaptureDevice *))
{
	AVCaptureDevice *device = state().device;
	if (!device) return false;
	NSError *error = nil;
	if (![device lockForConfiguration:&error]) return false;
	body(device);
	[device unlockForConfiguration];
	return true;
}

}  // namespace

bool Camera::isAvailable()
{
	return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] != nil;
}

bool Camera::hasPermission()
{
	return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized;
}

bool Camera::requestPermission()
{
	// Synchronous facade: kick off the prompt; callers poll hasPermission().
	if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
		[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL){
		}];
	}
	return hasPermission();
}

bool Camera::open(const std::string &facingHint, int preferredWidth, int preferredHeight)
{
	(void)preferredWidth;
	(void)preferredHeight;
	close();
	auto &s = state();

	Facing facing = Facing::Back;
	const AVCaptureDevicePosition position = positionForHint(facingHint, facing);
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
	                                                            mediaType:AVMediaTypeVideo
	                                                             position:position];
	if (!device) device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if (!device) return false;

	NSError *error = nil;
	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (!input) return false;

	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	if ([session canSetSessionPreset:AVCaptureSessionPresetHigh]) session.sessionPreset = AVCaptureSessionPresetHigh;
	if (![session canAddInput:input]) return false;
	[session addInput:input];

	AVCaptureVideoDataOutput *dataOutput = [[AVCaptureVideoDataOutput alloc] init];
	dataOutput.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
	dataOutput.alwaysDiscardsLateVideoFrames = YES;
	GeaCameraFrameSink *sink = [[GeaCameraFrameSink alloc] init];
	dispatch_queue_t queue = dispatch_queue_create("com.gea.camera.frames", DISPATCH_QUEUE_SERIAL);
	[dataOutput setSampleBufferDelegate:sink queue:queue];
	if ([session canAddOutput:dataOutput]) [session addOutput:dataOutput];

	AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
	previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

	s.session = session;
	s.device = device;
	s.input = input;
	s.dataOutput = dataOutput;
	s.frameSink = sink;
	s.sampleQueue = queue;
	s.previewLayer = previewLayer;
	s.facing = facing;
	s.mirror = (facing == Facing::Front);
	s.open = true;

	dispatch_async(dispatch_get_main_queue(), ^{
		UIView *host = gea_ios_camera_host_view();
		if (host && state().previewLayer) {
			state().previewLayer.frame = host.bounds;
			[host.layer addSublayer:state().previewLayer];
		}
	});
	[session startRunning];
	return true;
}

void Camera::close()
{
	auto &s = state();
	if (s.session) [s.session stopRunning];
	AVCaptureVideoPreviewLayer *layer = s.previewLayer;
	dispatch_async(dispatch_get_main_queue(), ^{
		[layer removeFromSuperlayer];
	});
	s.session = nil;
	s.device = nil;
	s.input = nil;
	s.dataOutput = nil;
	s.frameSink = nil;
	s.sampleQueue = nullptr;
	s.previewLayer = nil;
	s.open = false;
	{
		std::lock_guard<std::mutex> lock(s.frameMutex);
		s.latestFrame.clear();
		s.latestWidth = 0;
		s.latestHeight = 0;
	}
}

bool Camera::isOpen() { return state().open; }
int Camera::width() { return state().width; }
int Camera::height() { return state().height; }
int Camera::orientation() { return 0; }
Facing Camera::currentFacing() { return state().facing; }

std::string Camera::currentFacingString()
{
	switch (state().facing) {
	case Facing::Front: return "front";
	case Facing::External: return "external";
	case Facing::Back:
	default: return "back";
	}
}

int Camera::deviceCount()
{
	int count = 0;
	if ([AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
	                                       mediaType:AVMediaTypeVideo
	                                        position:AVCaptureDevicePositionBack]) {
		++count;
	}
	if ([AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
	                                       mediaType:AVMediaTypeVideo
	                                        position:AVCaptureDevicePositionFront]) {
		++count;
	}
	return count > 0 ? count : 1;
}

DeviceInfo Camera::deviceAt(int index)
{
	if (index == 1) return {"front", Facing::Front, 0, 0};
	return {"back", Facing::Back, 0, 0};
}

int Camera::previewMode() { return 1; }  // NativeOverlay

bool Camera::fillPreview(gea::framework::graphics::pixel::native_t *, int, int, int, bool)
{
	// NativeOverlay: the AVCaptureVideoPreviewLayer renders the preview; the
	// runtime never asks us to fill a framebuffer.
	return false;
}

// NativeOverlay mode: the AVCaptureVideoPreviewLayer is positioned/composited by
// the iOS renderer, so there is no framework-driven overlay present step here.
void Camera::presentNativeOverlay() {}

void Camera::positionPreviewLayer(int x, int y, int width, int height)
{
	AVCaptureVideoPreviewLayer *layer = state().previewLayer;
	if (!layer) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIView *host = gea_ios_camera_host_view();
		if (!host) return;
		if (layer.superlayer != host.layer) [host.layer addSublayer:layer];
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		layer.hidden = NO;
		layer.frame = canvasRectToViewPoints(host, x, y, width, height);
		[CATransaction commit];
	});
}

void Camera::hidePreviewLayer()
{
	AVCaptureVideoPreviewLayer *layer = state().previewLayer;
	if (!layer) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		layer.hidden = YES;
	});
}

int Camera::capture(bool mirror)
{
	auto &s = state();
	std::lock_guard<std::mutex> lock(s.frameMutex);
	if (s.latestFrame.empty() || s.latestWidth <= 0 || s.latestHeight <= 0) return -1;
	const int w = s.latestWidth;
	const int h = s.latestHeight;
	const bool mir = mirror || s.mirror;
	auto *pixels = static_cast<std::uint32_t *>(std::malloc(sizeof(std::uint32_t) * w * h));
	if (!pixels) return -1;
	for (int y = 0; y < h; ++y) {
		const std::uint32_t *src = s.latestFrame.data() + static_cast<std::size_t>(y) * w;
		std::uint32_t *dst = pixels + static_cast<std::size_t>(y) * w;
		if (mir) {
			for (int x = 0; x < w; ++x) dst[x] = src[w - 1 - x];
		} else {
			std::memcpy(dst, src, sizeof(std::uint32_t) * w);
		}
	}
	// pixels is RGBA8888, which is exactly pixel::native_t on iOS — register it as
	// a native buffer and transfer ownership to the store (freed on dispose).
	const int id = gea::framework::graphics::ImageStore::instance().registerBuffer(pixels, w, h, -1, /*takeOwnership=*/true);
	if (id < 0) std::free(pixels);
	return id;
}

bool Camera::startRecording(const std::string &, double) { return false; }  // movie: later
double Camera::stopRecording() { return -1.0; }
bool Camera::isRecording() { return false; }

void Camera::setFlash(const std::string &mode) { setTorch(mode, 0.0); }

void Camera::setZoom(double factor)
{
	withLockedConfig(^(AVCaptureDevice *device) {
		const CGFloat clamped = std::max<CGFloat>(1.0, std::min<CGFloat>(static_cast<CGFloat>(factor),
		                                                                  device.activeFormat.videoMaxZoomFactor));
		device.videoZoomFactor = clamped;
	});
}

void Camera::setMirror(bool mirror) { state().mirror = mirror; }

void Camera::setExposure(const std::string &mode, double bias, double iso, double durationMs)
{
	(void)iso;
	(void)durationMs;
	withLockedConfig(^(AVCaptureDevice *device) {
		if (mode == "locked" || mode == "manual") {
			if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) device.exposureMode = AVCaptureExposureModeLocked;
		} else if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
			device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
		}
		if (bias != 0.0) {
			const float clamped = std::max(device.minExposureTargetBias,
			                               std::min(device.maxExposureTargetBias, static_cast<float>(bias)));
			[device setExposureTargetBias:clamped completionHandler:nil];
		}
	});
}

void Camera::setWhiteBalance(const std::string &mode, double temperatureK, double tint)
{
	withLockedConfig(^(AVCaptureDevice *device) {
		if (mode == "locked") {
			if (temperatureK > 0.0 &&
			    [device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
				AVCaptureWhiteBalanceTemperatureAndTintValues values;
				values.temperature = static_cast<float>(temperatureK);
				values.tint = static_cast<float>(tint);
				AVCaptureWhiteBalanceGains gains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:values];
				const CGFloat maxGain = device.maxWhiteBalanceGain;
				gains.redGain = std::max<CGFloat>(1.0, std::min<CGFloat>(gains.redGain, maxGain));
				gains.greenGain = std::max<CGFloat>(1.0, std::min<CGFloat>(gains.greenGain, maxGain));
				gains.blueGain = std::max<CGFloat>(1.0, std::min<CGFloat>(gains.blueGain, maxGain));
				[device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:gains completionHandler:nil];
			} else if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked]) {
				device.whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
			}
		} else if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
			device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
		}
	});
}

void Camera::setFocus(const std::string &mode, double pointX, double pointY)
{
	withLockedConfig(^(AVCaptureDevice *device) {
		if ((pointX != 0.0 || pointY != 0.0) && device.isFocusPointOfInterestSupported) {
			device.focusPointOfInterest = CGPointMake(static_cast<CGFloat>(pointX), static_cast<CGFloat>(pointY));
		}
		if (mode == "locked") {
			if ([device isFocusModeSupported:AVCaptureFocusModeLocked]) device.focusMode = AVCaptureFocusModeLocked;
		} else if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
			device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
		}
	});
}

void Camera::setTorch(const std::string &mode, double level)
{
	withLockedConfig(^(AVCaptureDevice *device) {
		if (!device.hasTorch) return;
		if (mode == "on") {
			const float lvl = level > 0.0 ? static_cast<float>(level) : AVCaptureMaxAvailableTorchLevel;
			[device setTorchModeOnWithLevel:lvl error:nil];
		} else if (mode == "auto") {
			if ([device isTorchModeSupported:AVCaptureTorchModeAuto]) device.torchMode = AVCaptureTorchModeAuto;
		} else {
			device.torchMode = AVCaptureTorchModeOff;
		}
	});
}

}  // namespace gea::platform::camera

@implementation GeaCameraFrameSink
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection
{
	(void)output;
	(void)connection;
	gea::platform::camera::storeLatestFrame(CMSampleBufferGetImageBuffer(sampleBuffer));
}
@end

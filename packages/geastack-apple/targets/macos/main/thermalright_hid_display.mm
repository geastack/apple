#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <ImageIO/ImageIO.h>

#include "pixel.h"
#include "thermalright_hid_display.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifndef GEA_EMBEDDED_DISPLAY_WIDTH
#define GEA_EMBEDDED_DISPLAY_WIDTH 1280
#endif
#ifndef GEA_EMBEDDED_DISPLAY_HEIGHT
#define GEA_EMBEDDED_DISPLAY_HEIGHT 480
#endif
#ifndef GEA_MACOS_THERMALRIGHT_PRODUCT_ID
#define GEA_MACOS_THERMALRIGHT_PRODUCT_ID 0
#endif

namespace {

constexpr int kVendorId = 0x0416;
constexpr int kDefaultWidth = GEA_EMBEDDED_DISPLAY_WIDTH;
constexpr int kDefaultHeight = GEA_EMBEDDED_DISPLAY_HEIGHT;
constexpr int kReportBytes = 512;
constexpr std::uint8_t kMagic[4] = {0xDA, 0xDB, 0xDC, 0xDD};
constexpr int kLyChunkBytes = 512;
constexpr int kLyChunkHeaderBytes = 16;
constexpr int kLyChunkPayloadBytes = 496;
constexpr int kLyBurstBytes = 4096;

enum class Transport {
  Hid,
  LyBulk,
};

struct DeviceProfile {
  int productId;
  int width;
  int height;
  const char *name;
  Transport transport;
  int rotationDegrees;
};

constexpr DeviceProfile kDeviceProfiles[] = {
    {0x5302, 1280, 480, "1280x480 HID", Transport::Hid, 0},
    {0x5408, 1920, 462, "1920x462 LY bulk", Transport::LyBulk, 180},
};

const DeviceProfile *profileForProduct(int productId) {
  for (const auto &profile : kDeviceProfiles) {
    if (profile.productId == productId)
      return &profile;
  }
  return nullptr;
}

const DeviceProfile *profileForSize(int width, int height) {
  for (const auto &profile : kDeviceProfiles) {
    if (profile.width == width && profile.height == height)
      return &profile;
  }
  return nullptr;
}

bool truthy(const char *value) {
  if (!value || !*value)
    return false;
  if (std::strcmp(value, "0") == 0)
    return false;
  if (std::strcmp(value, "false") == 0)
    return false;
  if (std::strcmp(value, "FALSE") == 0)
    return false;
  if (std::strcmp(value, "off") == 0)
    return false;
  if (std::strcmp(value, "OFF") == 0)
    return false;
  return true;
}

bool selectedByEnv() {
  if (truthy(std::getenv("GEA_MACOS_THERMALRIGHT_DISPLAY")))
    return true;
  const char *target = std::getenv("GEA_MACOS_DISPLAY_TARGET");
  if (!target)
    return false;
  return std::strcmp(target, "thermalright") == 0 ||
         std::strcmp(target, "thermalright-hid") == 0 ||
         std::strcmp(target, "thermalright-usb") == 0 ||
         std::strcmp(target, "thermalright-wide") == 0 ||
         std::strcmp(target, "thermalright-hid-wide") == 0 ||
         std::strcmp(target, "thermalright-usb-wide") == 0 ||
         std::strcmp(target, "thermalright-1280x480") == 0 ||
         std::strcmp(target, "thermalright-hid-1280x480") == 0 ||
         std::strcmp(target, "thermalright-1920x462") == 0 ||
         std::strcmp(target, "thermalright-ly-1920x462") == 0 ||
         std::strcmp(target, "thermalright-1920x480") == 0 ||
         std::strcmp(target, "thermalright-hid-1920x480") == 0;
}

int envInt(const char *name, int fallback) {
  const char *value = std::getenv(name);
  if (!value || !*value)
    return fallback;
  const int parsed = std::atoi(value);
  return parsed > 0 ? parsed : fallback;
}

int envIntBase0(const char *name, int fallback) {
  const char *value = std::getenv(name);
  if (!value || !*value)
    return fallback;
  char *end = nullptr;
  const long parsed = std::strtol(value, &end, 0);
  return end && *end == '\0' && parsed > 0 ? static_cast<int>(parsed)
                                           : fallback;
}

double envDouble(const char *name, double fallback) {
  const char *value = std::getenv(name);
  if (!value || !*value)
    return fallback;
  char *end = nullptr;
  const double parsed = std::strtod(value, &end);
  return end && *end == '\0' && parsed > 0.0 ? parsed : fallback;
}

void writeLe16(std::uint8_t *dst, std::uint16_t value) {
  dst[0] = static_cast<std::uint8_t>(value & 0xFF);
  dst[1] = static_cast<std::uint8_t>((value >> 8) & 0xFF);
}

void writeLe32(std::uint8_t *dst, std::uint32_t value) {
  dst[0] = static_cast<std::uint8_t>(value & 0xFF);
  dst[1] = static_cast<std::uint8_t>((value >> 8) & 0xFF);
  dst[2] = static_cast<std::uint8_t>((value >> 16) & 0xFF);
  dst[3] = static_cast<std::uint8_t>((value >> 24) & 0xFF);
}

std::size_t alignReport(std::size_t value) {
  return (value + static_cast<std::size_t>(kReportBytes - 1)) &
         ~static_cast<std::size_t>(kReportBytes - 1);
}

void addInt(CFMutableDictionaryRef dict, const void *key, int value) {
  CFNumberRef number =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
  if (!number)
    return;
  CFDictionarySetValue(dict, key, number);
  CFRelease(number);
}

int deviceInt(IOHIDDeviceRef device, CFStringRef key, int fallback = 0) {
  if (!device)
    return fallback;
  CFTypeRef value = IOHIDDeviceGetProperty(device, key);
  if (!value || CFGetTypeID(value) != CFNumberGetTypeID())
    return fallback;
  int out = fallback;
  CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberIntType, &out);
  return out;
}

int serviceInt(io_service_t service, CFStringRef key, int fallback = 0) {
  CFTypeRef value =
      IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
  if (!value)
    return fallback;
  int out = fallback;
  if (CFGetTypeID(value) == CFNumberGetTypeID()) {
    CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberIntType, &out);
  }
  CFRelease(value);
  return out;
}

class ThermalrightHidDisplay {
public:
  ThermalrightHidDisplay()
      : width_(envInt("GEA_MACOS_THERMALRIGHT_WIDTH", kDefaultWidth)),
        height_(envInt("GEA_MACOS_THERMALRIGHT_HEIGHT", kDefaultHeight)),
        preferredProductId_(envIntBase0("GEA_MACOS_THERMALRIGHT_PRODUCT_ID",
                                        GEA_MACOS_THERMALRIGHT_PRODUCT_ID)),
        fps_(std::clamp(envInt("GEA_MACOS_THERMALRIGHT_FPS", 30), 1, 60)),
        jpegQuality_(std::clamp(
            envDouble("GEA_MACOS_THERMALRIGHT_JPEG_QUALITY", 0.45), 0.1, 1.0)) {
    if (preferredProductId_ <= 0) {
      if (const DeviceProfile *profile = profileForSize(width_, height_)) {
        preferredProductId_ = profile->productId;
      }
    }
  }

  ~ThermalrightHidDisplay() {
    stopWorker();
    close();
  }

  int width() const { return width_; }
  int height() const { return height_; }
  int fps() const { return fps_; }

  bool submitRgb565(const std::uint16_t *pixels, int width, int height) {
    if (!pixels || width <= 0 || height <= 0)
      return false;
    startWorker();
    const std::size_t pixelCount =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    {
      std::lock_guard<std::mutex> lock(frameMutex_);
      pendingPixels_.assign(pixels, pixels + pixelCount);
      pendingWidth_ = width;
      pendingHeight_ = height;
      pendingGeneration_++;
    }
    frameCv_.notify_one();
    return true;
  }

  void close() {
    if (device_) {
      IOHIDDeviceClose(device_, kIOHIDOptionsTypeNone);
      CFRelease(device_);
      device_ = nullptr;
    }
    if (manager_) {
      IOHIDManagerClose(manager_, kIOHIDOptionsTypeNone);
      CFRelease(manager_);
      manager_ = nullptr;
    }
    if (usbInterface_) {
      (*usbInterface_)->USBInterfaceClose(usbInterface_);
      (*usbInterface_)->Release(usbInterface_);
      usbInterface_ = nullptr;
    }
    usbInPipe_ = 0;
    usbOutPipe_ = 0;
    activeProfile_ = nullptr;
    connected_ = false;
  }

private:
  using Clock = std::chrono::steady_clock;

  void startWorker() {
    std::lock_guard<std::mutex> lock(frameMutex_);
    if (workerRunning_)
      return;
    stopWorker_ = false;
    workerRunning_ = true;
    worker_ = std::thread([this] { workerLoop(); });
  }

  void stopWorker() {
    {
      std::lock_guard<std::mutex> lock(frameMutex_);
      if (!workerRunning_)
        return;
      stopWorker_ = true;
    }
    frameCv_.notify_one();
    if (worker_.joinable())
      worker_.join();
  }

  void workerLoop() {
    std::vector<std::uint16_t> framePixels;
    std::uint64_t consumedGeneration = 0;
    for (;;) {
      {
        std::unique_lock<std::mutex> lock(frameMutex_);
        frameCv_.wait(lock, [&] {
          return stopWorker_ || pendingGeneration_ != consumedGeneration;
        });
        if (stopWorker_)
          break;
      }

      Clock::time_point frameStart{};
      if (!beginFrame(&frameStart))
        continue;

      int frameWidth = 0;
      int frameHeight = 0;
      {
        std::lock_guard<std::mutex> lock(frameMutex_);
        if (stopWorker_)
          break;
        consumedGeneration = pendingGeneration_;
        frameWidth = pendingWidth_;
        frameHeight = pendingHeight_;
        framePixels.assign(pendingPixels_.begin(), pendingPixels_.end());
      }
      @autoreleasepool {
        submitRgb565Sync(framePixels.data(), frameWidth, frameHeight,
                         frameStart);
      }
    }
    close();
    {
      std::lock_guard<std::mutex> lock(frameMutex_);
      workerRunning_ = false;
    }
  }

  bool submitRgb565Sync(const std::uint16_t *pixels, int width, int height,
                        Clock::time_point frameStart) {
    if (!pixels || width <= 0 || height <= 0)
      return false;
    bool ok = false;
    if (!connect()) {
      finishFrame(frameStart);
      return false;
    }

    const auto encodeStart = Clock::now();
    NSData *jpeg = encodeJpeg(pixels, width, height);
    const auto encodeEnd = Clock::now();
    const auto payloadBytes =
        jpeg ? static_cast<std::size_t>([jpeg length]) : 0;
    const int reportCount = transferUnitCount(payloadBytes);
    const auto writeStart = Clock::now();
    if (jpeg && [jpeg length] > 0)
      ok = writeJpeg(jpeg, width, height);
    const auto writeEnd = Clock::now();
    if (ok) {
      recordFrame(payloadBytes, reportCount,
                  std::chrono::duration_cast<std::chrono::microseconds>(
                      encodeEnd - encodeStart)
                      .count(),
                  std::chrono::duration_cast<std::chrono::microseconds>(
                      writeEnd - writeStart)
                      .count());
    }
    finishFrame(frameStart);
    if (!ok)
      close();
    return ok;
  }

  std::chrono::microseconds frameInterval() const {
    return std::chrono::microseconds((1000000 + fps_ / 2) / fps_);
  }

  bool beginFrame(Clock::time_point *frameStart) {
    auto now = Clock::now();
    if (nextSubmit_.time_since_epoch().count() == 0)
      nextSubmit_ = now;
    if (now < nextSubmit_) {
      std::this_thread::sleep_until(nextSubmit_);
      now = Clock::now();
    }
    if (frameStart)
      *frameStart = now;
    return true;
  }

  void finishFrame(Clock::time_point frameStart) {
    const auto interval = frameInterval();
    const auto now = Clock::now();
    if (nextSubmit_.time_since_epoch().count() == 0 ||
        nextSubmit_ < frameStart) {
      nextSubmit_ = frameStart;
    }
    do {
      nextSubmit_ += interval;
    } while (nextSubmit_ <= now);
  }

  void recordFrame(std::size_t payloadBytes, int reportCount,
                   std::int64_t encodeUs, std::int64_t writeUs) {
    const auto now = Clock::now();
    if (statsWindowStart_.time_since_epoch().count() == 0)
      statsWindowStart_ = now;
    statsFrames_++;
    statsPayloadBytes_ += payloadBytes;
    statsReportCount_ += reportCount;
    statsEncodeUs_ += encodeUs;
    statsWriteUs_ += writeUs;

    const auto elapsedUs =
        std::chrono::duration_cast<std::chrono::microseconds>(now -
                                                              statsWindowStart_)
            .count();
    if (elapsedUs < 1000000)
      return;
    const double elapsedSeconds = static_cast<double>(elapsedUs) / 1000000.0;
    const double frameCount = static_cast<double>(statsFrames_);
    NSLog(@"[gea-thermalright] %.1ffps q=%.2f jpeg=%.1fKB reports=%.1f "
          @"encode=%.1fms write=%.1fms",
          frameCount / elapsedSeconds, jpegQuality_,
          (static_cast<double>(statsPayloadBytes_) / frameCount) / 1024.0,
          static_cast<double>(statsReportCount_) / frameCount,
          (static_cast<double>(statsEncodeUs_) / frameCount) / 1000.0,
          (static_cast<double>(statsWriteUs_) / frameCount) / 1000.0);
    statsWindowStart_ = now;
    statsFrames_ = 0;
    statsPayloadBytes_ = 0;
    statsReportCount_ = 0;
    statsEncodeUs_ = 0;
    statsWriteUs_ = 0;
  }

  int transferUnitCount(std::size_t payloadBytes) const {
    if (payloadBytes == 0)
      return 0;
    const DeviceProfile *profile = activeProfile();
    if (profile && profile->transport == Transport::LyBulk) {
      std::size_t chunks = payloadBytes / kLyChunkPayloadBytes + 1;
      const std::size_t remainder = chunks % 4;
      if (remainder != 0)
        chunks += 4 - remainder;
      return static_cast<int>(chunks);
    }
    return static_cast<int>(alignReport(20 + payloadBytes) / kReportBytes);
  }

  const DeviceProfile *activeProfile() const {
    if (activeProfile_)
      return activeProfile_;
    if (const DeviceProfile *profile = profileForProduct(preferredProductId_))
      return profile;
    return profileForSize(width_, height_);
  }

  bool connect() {
    const DeviceProfile *profile = activeProfile();
    if (connected_) {
      if (profile && profile->transport == Transport::LyBulk)
        return usbInterface_ != nullptr;
      return device_ != nullptr;
    }
    const auto now = Clock::now();
    if (lastConnectAttempt_.time_since_epoch().count() != 0 &&
        now - lastConnectAttempt_ < std::chrono::milliseconds(1000)) {
      return false;
    }
    lastConnectAttempt_ = now;

    close();
    profile = activeProfile();
    if (profile && profile->transport == Transport::LyBulk)
      return connectLyBulk(profile);
    return connectHid(profile);
  }

  bool connectHid(const DeviceProfile *requestedProfile) {
    manager_ = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager_)
      return false;

    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if (!match) {
      close();
      return false;
    }
    addInt(match, CFSTR(kIOHIDVendorIDKey), kVendorId);
    if (preferredProductId_ > 0) {
      addInt(match, CFSTR(kIOHIDProductIDKey), preferredProductId_);
    }
    IOHIDManagerSetDeviceMatching(manager_, match);
    CFRelease(match);

    IOReturn opened = IOHIDManagerOpen(manager_, kIOHIDOptionsTypeNone);
    if (opened != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] IOHIDManagerOpen failed: 0x%08x", opened);
      close();
      return false;
    }

    CFSetRef devices = IOHIDManagerCopyDevices(manager_);
    if (!devices || CFSetGetCount(devices) <= 0) {
      if (devices)
        CFRelease(devices);
      NSLog(@"[gea-thermalright] no Thermalright HID display found (vid=0x%04x "
            @"preferred pid=0x%04x)",
            kVendorId, preferredProductId_);
      close();
      return false;
    }

    const CFIndex count = CFSetGetCount(devices);
    std::vector<const void *> values(static_cast<std::size_t>(count));
    CFSetGetValues(devices, values.data());
    const DeviceProfile *selectedProfile = nullptr;
    for (const void *value : values) {
      IOHIDDeviceRef candidate =
          static_cast<IOHIDDeviceRef>(const_cast<void *>(value));
      const int productId = deviceInt(candidate, CFSTR(kIOHIDProductIDKey));
      const DeviceProfile *profile = profileForProduct(productId);
      if (!profile)
        continue;
      if (profile->transport != Transport::Hid)
        continue;
      if (preferredProductId_ > 0 && productId != preferredProductId_)
        continue;
      if (requestedProfile && productId != requestedProfile->productId)
        continue;
      device_ = candidate;
      selectedProfile = profile;
      CFRetain(device_);
      break;
    }
    CFRelease(devices);
    if (!device_) {
      NSLog(@"[gea-thermalright] no supported HID profile found (vid=0x%04x "
            @"preferred pid=0x%04x)",
            kVendorId, preferredProductId_);
      close();
      return false;
    }

    opened = IOHIDDeviceOpen(device_, kIOHIDOptionsTypeNone);
    if (opened != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] IOHIDDeviceOpen failed: 0x%08x", opened);
      close();
      return false;
    }

    std::uint8_t init[kReportBytes] = {};
    std::memcpy(init, kMagic, sizeof(kMagic));
    init[12] = 0x01;
    IOReturn result = IOHIDDeviceSetReport(device_, kIOHIDReportTypeOutput, 0,
                                           init, sizeof(init));
    if (result != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] init report failed: 0x%08x", result);
      close();
      return false;
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(120));
    connected_ = true;
    activeProfile_ = selectedProfile;
    NSLog(@"[gea-thermalright] connected %s pid=0x%04x canvas=%dx%d @ %dfps",
          selectedProfile ? selectedProfile->name : "unknown",
          selectedProfile ? selectedProfile->productId
                          : deviceInt(device_, CFSTR(kIOHIDProductIDKey)),
          width_, height_, fps_);
    return true;
  }

  io_service_t findUsbInterfaceService(int productId) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostInterface");
    if (!match)
      return IO_OBJECT_NULL;

    io_iterator_t iterator = IO_OBJECT_NULL;
    IOReturn result =
        IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator);
    if (result != kIOReturnSuccess || iterator == IO_OBJECT_NULL) {
      NSLog(@"[gea-thermalright] USB interface match failed: 0x%08x", result);
      return IO_OBJECT_NULL;
    }

    io_service_t found = IO_OBJECT_NULL;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
      const bool isMatch =
          serviceInt(service, CFSTR("idVendor")) == kVendorId &&
          serviceInt(service, CFSTR("idProduct")) == productId &&
          serviceInt(service, CFSTR("bInterfaceNumber")) == 0 &&
          serviceInt(service, CFSTR("bInterfaceClass")) == 0xFF;
      if (isMatch) {
        found = service;
        break;
      }
      IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return found;
  }

  bool openUsbInterface(const DeviceProfile *profile) {
    if (!profile)
      return false;
    io_service_t service = findUsbInterfaceService(profile->productId);
    if (service == IO_OBJECT_NULL) {
      NSLog(@"[gea-thermalright] no Thermalright USB bulk interface found "
            @"(vid=0x%04x pid=0x%04x)",
            kVendorId, profile->productId);
      return false;
    }

    IOCFPlugInInterface **plugin = nullptr;
    SInt32 score = 0;
    IOReturn result = IOCreatePlugInInterfaceForService(
        service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID,
        &plugin, &score);
    IOObjectRelease(service);
    if (result != kIOReturnSuccess || !plugin) {
      NSLog(@"[gea-thermalright] IOUSB interface plugin failed: 0x%08x",
            result);
      return false;
    }

    IOUSBInterfaceInterface **interface = nullptr;
    HRESULT query = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
        reinterpret_cast<LPVOID *>(&interface));
    (*plugin)->Release(plugin);
    if (query != 0 || !interface) {
      NSLog(@"[gea-thermalright] IOUSB interface QueryInterface failed: 0x%08x",
            static_cast<unsigned>(query));
      return false;
    }

    result = (*interface)->USBInterfaceOpen(interface);
    if (result != kIOReturnSuccess) {
      IOReturn seize = (*interface)->USBInterfaceOpenSeize(interface);
      NSLog(
          @"[gea-thermalright] USBInterfaceOpen failed: 0x%08x, seize: 0x%08x",
          result, seize);
      result = seize;
    }
    if (result != kIOReturnSuccess) {
      (*interface)->Release(interface);
      return false;
    }

    UInt8 endpointCount = 0;
    result = (*interface)->GetNumEndpoints(interface, &endpointCount);
    if (result != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] GetNumEndpoints failed: 0x%08x", result);
      (*interface)->USBInterfaceClose(interface);
      (*interface)->Release(interface);
      return false;
    }

    UInt8 inPipe = 0;
    UInt8 outPipe = 0;
    for (UInt8 pipe = 1; pipe <= endpointCount; pipe++) {
      UInt8 direction = 0;
      UInt8 number = 0;
      UInt8 transferType = 0;
      UInt16 maxPacketSize = 0;
      UInt8 interval = 0;
      result =
          (*interface)
              ->GetPipeProperties(interface, pipe, &direction, &number,
                                  &transferType, &maxPacketSize, &interval);
      if (result != kIOReturnSuccess)
        continue;
      NSLog(@"[gea-thermalright] USB pipe %u ep=%u dir=%u type=%u mps=%u", pipe,
            number, direction, transferType, maxPacketSize);
      if (transferType != kUSBBulk)
        continue;
      if (direction == kUSBIn && !inPipe)
        inPipe = pipe;
      if (direction == kUSBOut && !outPipe)
        outPipe = pipe;
    }

    if (!inPipe || !outPipe) {
      NSLog(@"[gea-thermalright] missing LY bulk pipes (in=%u out=%u)", inPipe,
            outPipe);
      (*interface)->USBInterfaceClose(interface);
      (*interface)->Release(interface);
      return false;
    }

    usbInterface_ = interface;
    usbInPipe_ = inPipe;
    usbOutPipe_ = outPipe;
    (*usbInterface_)->ClearPipeStallBothEnds(usbInterface_, usbInPipe_);
    (*usbInterface_)->ClearPipeStallBothEnds(usbInterface_, usbOutPipe_);
    return true;
  }

  bool connectLyBulk(const DeviceProfile *profile) {
    if (!openUsbInterface(profile))
      return false;

    std::vector<std::uint8_t> handshake(2048, 0);
    handshake[0] = 0x02;
    handshake[1] = 0xFF;
    handshake[8] = 0x01;
    if (!writeUsb(handshake.data(), handshake.size(), 1000, "LY handshake")) {
      close();
      return false;
    }

    std::uint8_t response[kReportBytes] = {};
    UInt32 responseSize = sizeof(response);
    IOReturn ack = (*usbInterface_)
                       ->ReadPipeTO(usbInterface_, usbInPipe_, response,
                                    &responseSize, 100, 100);
    if (ack == kIOReturnSuccess && responseSize >= 9 && response[0] == 0x03 &&
        response[1] == 0xFF && response[8] == 0x01) {
      NSLog(@"[gea-thermalright] LY handshake ack %u bytes: %02x %02x %02x",
            responseSize, response[0], response[1], response[8]);
    } else {
      NSLog(@"[gea-thermalright] LY handshake ack not available: 0x%08x", ack);
      close();
      return false;
    }

    connected_ = true;
    activeProfile_ = profile;
    lyAckWarningLogged_ = false;
    NSLog(@"[gea-thermalright] connected %s pid=0x%04x canvas=%dx%d @ %dfps",
          profile->name, profile->productId, width_, height_, fps_);
    return true;
  }

  NSData *encodeJpeg(const std::uint16_t *pixels, int width, int height) {
    const std::size_t pixelCount =
        static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    rgbaScratch_.resize(pixelCount * 4);
    const bool flip180 = rotate180();
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        const std::size_t dst =
            static_cast<std::size_t>(y) * static_cast<std::size_t>(width) +
            static_cast<std::size_t>(x);
        const std::size_t src =
            flip180 ? static_cast<std::size_t>(height - 1 - y) *
                              static_cast<std::size_t>(width) +
                          static_cast<std::size_t>(width - 1 - x)
                    : dst;
        int r, g, b;
        gea::framework::graphics::pixel::unpackRgb565(pixels[src], &r, &g, &b);
        rgbaScratch_[dst * 4 + 0] =
            static_cast<std::uint8_t>((r * 255 + 15) / 31);
        rgbaScratch_[dst * 4 + 1] =
            static_cast<std::uint8_t>((g * 255 + 31) / 63);
        rgbaScratch_[dst * 4 + 2] =
            static_cast<std::uint8_t>((b * 255 + 15) / 31);
        rgbaScratch_[dst * 4 + 3] = 0xFF;
      }
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        nullptr, rgbaScratch_.data(), rgbaScratch_.size(), nullptr);
    if (!colorSpace || !provider) {
      if (provider)
        CGDataProviderRelease(provider);
      if (colorSpace)
        CGColorSpaceRelease(colorSpace);
      return nil;
    }

    const CGBitmapInfo bitmapInfo =
        static_cast<CGBitmapInfo>(kCGImageAlphaNoneSkipLast) | static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big);
    CGImageRef image = CGImageCreate(
        static_cast<std::size_t>(width), static_cast<std::size_t>(height), 8,
        32, static_cast<std::size_t>(width) * 4, colorSpace, bitmapInfo,
        provider, nullptr, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    if (!image)
      return nil;

    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, CFSTR("public.jpeg"), 1, nullptr);
    if (!destination) {
      CGImageRelease(image);
      return nil;
    }

    NSDictionary *properties = @{
      (__bridge NSString *)
      kCGImageDestinationLossyCompressionQuality : @(jpegQuality_)
    };
    CGImageDestinationAddImage(destination, image,
                               (__bridge CFDictionaryRef)properties);
    const bool ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    return ok ? data : nil;
  }

  bool rotate180() const {
    if (const char *value = std::getenv("GEA_MACOS_THERMALRIGHT_ROTATE")) {
      return std::atoi(value) == 180;
    }
    const DeviceProfile *profile = activeProfile();
    return profile && profile->rotationDegrees == 180;
  }

  bool writeReport(const std::uint8_t *report) {
    if (!device_ || !report)
      return false;
    IOReturn result = IOHIDDeviceSetReport(device_, kIOHIDReportTypeOutput, 0,
                                           report, kReportBytes);
    if (result != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] HID write failed: 0x%08x", result);
      return false;
    }
    return true;
  }

  bool writeJpeg(NSData *jpeg, int width, int height) {
    const DeviceProfile *profile = activeProfile();
    if (profile && profile->transport == Transport::LyBulk)
      return writeLyJpeg(jpeg);
    return writeHidJpeg(jpeg, width, height);
  }

  bool writeHidJpeg(NSData *jpeg, int width, int height) {
    const std::size_t payloadBytes = [jpeg length];
    const std::size_t packetBytes = alignReport(20 + payloadBytes);
    packetScratch_.assign(packetBytes, 0);
    std::memcpy(packetScratch_.data(), kMagic, sizeof(kMagic));
    packetScratch_[4] = 0x02;
    packetScratch_[5] = 0x00;
    packetScratch_[6] = 0x00; // JPEG
    packetScratch_[7] = 0x00;
    writeLe16(packetScratch_.data() + 8, static_cast<std::uint16_t>(width));
    writeLe16(packetScratch_.data() + 10, static_cast<std::uint16_t>(height));
    packetScratch_[12] = 0x02;
    packetScratch_[13] = 0x00;
    packetScratch_[14] = 0x00;
    packetScratch_[15] = 0x00;
    writeLe32(packetScratch_.data() + 16,
              static_cast<std::uint32_t>(payloadBytes));
    std::memcpy(packetScratch_.data() + 20, [jpeg bytes], payloadBytes);

    for (std::size_t offset = 0; offset < packetScratch_.size();
         offset += kReportBytes) {
      if (!writeReport(packetScratch_.data() + offset))
        return false;
    }
    return true;
  }

  bool writeUsb(const std::uint8_t *data, std::size_t size, UInt32 timeoutMs,
                const char *label) {
    if (!usbInterface_ || !usbOutPipe_ || !data)
      return false;
    IOReturn result =
        (*usbInterface_)
            ->WritePipeTO(usbInterface_, usbOutPipe_,
                          const_cast<std::uint8_t *>(data),
                          static_cast<UInt32>(size), timeoutMs, timeoutMs);
    if (result != kIOReturnSuccess) {
      NSLog(@"[gea-thermalright] USB %s write failed: 0x%08x (%zu bytes)",
            label ? label : "bulk", result, size);
      (*usbInterface_)->ClearPipeStallBothEnds(usbInterface_, usbOutPipe_);
      return false;
    }
    return true;
  }

  void readLyAck() {
    if (!usbInterface_ || !usbInPipe_)
      return;
    std::uint8_t ack[kReportBytes] = {};
    UInt32 size = sizeof(ack);
    IOReturn result =
        (*usbInterface_)
            ->ReadPipeTO(usbInterface_, usbInPipe_, ack, &size, 1000, 1000);
    if (result == kIOReturnSuccess)
      return;
    if (!lyAckWarningLogged_) {
      NSLog(@"[gea-thermalright] LY frame ack not available: 0x%08x", result);
      lyAckWarningLogged_ = true;
    }
  }

  bool writeLyJpeg(NSData *jpeg) {
    const std::size_t payloadBytes = [jpeg length];
    const std::uint8_t *payload =
        static_cast<const std::uint8_t *>([jpeg bytes]);
    if (!payload || payloadBytes == 0)
      return false;

    std::size_t chunkCount = payloadBytes / kLyChunkPayloadBytes + 1;
    const std::size_t lastChunkBytes = payloadBytes % kLyChunkPayloadBytes;
    std::size_t paddedChunkCount = chunkCount;
    const std::size_t remainder = paddedChunkCount % 4;
    if (remainder != 0)
      paddedChunkCount += 4 - remainder;

    lyScratch_.assign(paddedChunkCount * kLyChunkBytes, 0);
    for (std::size_t i = 0; i < chunkCount; i++) {
      std::uint8_t *chunk = lyScratch_.data() + i * kLyChunkBytes;
      const bool isLast = i == chunkCount - 1;
      const std::size_t dataBytes =
          isLast ? lastChunkBytes : kLyChunkPayloadBytes;
      chunk[0] = 0x01;
      chunk[1] = 0xFF;
      writeLe32(chunk + 2, static_cast<std::uint32_t>(payloadBytes));
      writeLe16(chunk + 6, static_cast<std::uint16_t>(dataBytes));
      chunk[8] = 0x01;
      writeLe16(chunk + 9, static_cast<std::uint16_t>(chunkCount));
      writeLe16(chunk + 11, static_cast<std::uint16_t>(i));
      const std::size_t srcOffset = i * kLyChunkPayloadBytes;
      if (dataBytes > 0) {
        std::memcpy(chunk + kLyChunkHeaderBytes, payload + srcOffset,
                    dataBytes);
      }
    }

    std::size_t offset = 0;
    while (offset < lyScratch_.size()) {
      const std::size_t remaining = lyScratch_.size() - offset;
      const std::size_t writeBytes =
          remaining >= kLyBurstBytes ? kLyBurstBytes
                                     : std::min<std::size_t>(2048, remaining);
      if (!writeUsb(lyScratch_.data() + offset, writeBytes, 5000, "LY frame"))
        return false;
      offset += writeBytes;
    }
    readLyAck();
    return true;
  }

  int width_ = kDefaultWidth;
  int height_ = kDefaultHeight;
  int preferredProductId_ = GEA_MACOS_THERMALRIGHT_PRODUCT_ID;
  int fps_ = 30;
  double jpegQuality_ = 0.45;
  IOHIDManagerRef manager_ = nullptr;
  IOHIDDeviceRef device_ = nullptr;
  IOUSBInterfaceInterface **usbInterface_ = nullptr;
  UInt8 usbInPipe_ = 0;
  UInt8 usbOutPipe_ = 0;
  const DeviceProfile *activeProfile_ = nullptr;
  bool connected_ = false;
  bool lyAckWarningLogged_ = false;
  Clock::time_point nextSubmit_{};
  Clock::time_point lastConnectAttempt_{};
  Clock::time_point statsWindowStart_{};
  int statsFrames_ = 0;
  std::size_t statsPayloadBytes_ = 0;
  int statsReportCount_ = 0;
  std::int64_t statsEncodeUs_ = 0;
  std::int64_t statsWriteUs_ = 0;
  std::vector<std::uint8_t> rgbaScratch_;
  std::vector<std::uint8_t> packetScratch_;
  std::vector<std::uint8_t> lyScratch_;
  std::mutex frameMutex_;
  std::condition_variable frameCv_;
  std::thread worker_;
  bool workerRunning_ = false;
  bool stopWorker_ = false;
  std::vector<std::uint16_t> pendingPixels_;
  int pendingWidth_ = 0;
  int pendingHeight_ = 0;
  std::uint64_t pendingGeneration_ = 0;
};

ThermalrightHidDisplay &display() {
  static ThermalrightHidDisplay instance;
  return instance;
}

} // namespace

namespace gea::macos::thermalright {

bool enabled() {
#if GEA_MACOS_THERMALRIGHT_DISPLAY_TARGET
  if (const char *value = std::getenv("GEA_MACOS_THERMALRIGHT_DISPLAY")) {
    return truthy(value);
  }
  return true;
#else
  return selectedByEnv();
#endif
}

int width() { return display().width(); }
int height() { return display().height(); }
int fps() { return display().fps(); }

bool submitRgb565(const std::uint16_t *pixels, int width, int height) {
  if (!enabled())
    return false;
  return display().submitRgb565(pixels, width, height);
}

void shutdown() { display().close(); }

} // namespace gea::macos::thermalright

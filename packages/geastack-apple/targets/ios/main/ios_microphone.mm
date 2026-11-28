// SPDX-License-Identifier: Apache-2.0
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <mutex>
#include <unordered_set>
#include "audio.h"
#include "host/media.h"

namespace gea::host::media {
namespace {
AVAudioEngine *capture;
std::unordered_set<NativeMediaTrackHandle> tracks;
std::mutex tracksMutex;
bool requestingPermission = false;

bool hasTracks() {
  std::lock_guard lock(tracksMutex);
  return !tracks.empty();
}

void stopCapture() {
  if (!capture) return;
  [capture.inputNode removeTapOnBus:0];
  [capture stop];
  capture = nil;
  [AVAudioSession.sharedInstance setActive:NO error:NULL];
}

void startCapture() {
  if (capture || !hasTracks()) return;
  AVAudioSession *session = AVAudioSession.sharedInstance;
  if (![session setCategory:AVAudioSessionCategoryRecord mode:AVAudioSessionModeMeasurement options:0 error:NULL] ||
      ![session setActive:YES error:NULL]) return;

  AVAudioEngine *engine = [[AVAudioEngine alloc] init];
  AVAudioInputNode *input = engine.inputNode;
  AVAudioFormat *source = [input outputFormatForBus:0];
  constexpr double sampleRate = gea::platform::audio::deviceSampleRate;
  AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:sampleRate channels:1 interleaved:YES];
  AVAudioConverter *converter = source.sampleRate > 0 && source.channelCount
      ? [[AVAudioConverter alloc] initFromFormat:source toFormat:format]
      : nil;
  if (!converter) {
    [session setActive:NO error:NULL];
    return;
  }
  [input installTapOnBus:0 bufferSize:2048 format:source block:^(AVAudioPCMBuffer *buffer, AVAudioTime *) {
    auto capacity = (AVAudioFrameCount)(buffer.frameLength * sampleRate / source.sampleRate) + 32;
    AVAudioPCMBuffer *pcm = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:capacity];
    __block BOOL sent = NO;
    [converter convertToBuffer:pcm error:NULL withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount, AVAudioConverterInputStatus *status) {
      *status = sent ? AVAudioConverterInputStatus_NoDataNow : AVAudioConverterInputStatus_HaveData;
      if (sent) return nil;
      sent = YES;
      return buffer;
    }];
    if (!pcm.frameLength) return;
    std::lock_guard lock(tracksMutex);
    for (const auto track : tracks) track_inject_pcm(track, pcm.int16ChannelData[0], pcm.frameLength);
  }];
  if (![engine startAndReturnError:NULL]) {
    [input removeTapOnBus:0];
    [session setActive:NO error:NULL];
    return;
  }
  capture = engine;
}

void requestCapture() {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  if (session.recordPermission == AVAudioSessionRecordPermissionGranted) {
    startCapture();
  } else if (session.recordPermission == AVAudioSessionRecordPermissionUndetermined && !requestingPermission) {
    requestingPermission = true;
    [session requestRecordPermission:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        requestingPermission = false;
        if (granted) startCapture();
      });
    }];
  }
}

void attach(NativeMediaTrackHandle track) {
  {
    std::lock_guard lock(tracksMutex);
    tracks.insert(track);
  }
  static dispatch_once_t observers;
  dispatch_once(&observers, ^{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UISceneDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
      stopCapture();
    }];
  });
  requestCapture();
}

void detach(NativeMediaTrackHandle track) {
  {
    std::lock_guard lock(tracksMutex);
    tracks.erase(track);
  }
  if (!hasTracks()) stopCapture();
}
} // namespace

void platform_attach_track(NativeMediaTrackHandle track) {
  if (NSThread.isMainThread) attach(track);
  else dispatch_async(dispatch_get_main_queue(), ^{ attach(track); });
}

void platform_detach_track(NativeMediaTrackHandle track) {
  if (NSThread.isMainThread) detach(track);
  else dispatch_async(dispatch_get_main_queue(), ^{ detach(track); });
}
} // namespace gea::host::media

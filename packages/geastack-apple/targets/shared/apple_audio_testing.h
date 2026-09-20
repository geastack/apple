// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstddef>

// Offline-rendering hooks for the Apple audio backend (targets/shared/apple_audio.mm).
//
// AVAudioEngine's manual-rendering mode drives the exact same graph the shipping
// build uses — source node, scheduler, envelope, mixer — without opening an
// output device. That makes the backend measurable (RMS, frequency) on a machine
// with no audio hardware and in CI, and it is what
// targets/shared/apple_audio_selftest.mm uses to prove the backend really
// synthesises sound.
//
// beginOfflineRendering() must be called before any other audio call: the engine
// graph is built lazily on first use and its mode is fixed at that point.

namespace gea::platform::audio::testing {

// Switches the (not yet started) engine into offline manual-rendering mode.
// Returns false if the engine is already running or the mode could not be set.
bool beginOfflineRendering(double sample_rate);

// Pulls `frames` frames from the engine into `interleaved_stereo`
// (2 floats per frame). Returns the number of frames actually rendered.
std::size_t renderOfflineFrames(float *interleaved_stereo, std::size_t frames);

// Sample rate the offline engine is actually running at.
double offlineSampleRate();

// Stops the engine and leaves manual-rendering mode.
void endOfflineRendering();

}  // namespace gea::platform::audio::testing

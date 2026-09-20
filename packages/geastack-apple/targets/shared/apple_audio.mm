// SPDX-License-Identifier: Apache-2.0
//
// Real Apple audio backend for gea::platform::audio — shared by the macOS and
// iOS targets (AVFoundation is on both; the only platform-conditional code is
// the iOS AVAudioSession activation).
//
// Shape
// -----
//   AVAudioEngine
//     ├─ AVAudioSourceNode  ── the synth: every OscillatorNode the app creates
//     │                        is rendered here, sample-accurately scheduled and
//     │                        mixed against every other live note.
//     ├─ AVAudioPlayerNode  ── AudioSystem::playFile
//     └─ AVAudioPlayerNode  ── AudioSystem::playPcm
//                     └─ mainMixerNode ─ outputNode
//
// Timebase
// --------
// AudioContext::currentTime() is the engine's own running time: frames rendered
// by the source node divided by the graph's sample rate (Web Audio semantics —
// it advances a render quantum at a time and sits slightly ahead of what the DAC
// has emitted). start(when)/stop(when) are converted to absolute frame numbers
// in that same timebase, so a note scheduled 150 ms out really starts 150 ms
// out. Before the engine is running (or if it never starts, e.g. no output
// device) currentTime() falls back to a steady wall clock so an app whose
// scheduler is driven off it keeps making progress instead of wedging; the
// frame offset is seeded from that clock when the engine does start, so the
// value is monotonic across the handover.
//
// Thread safety
// -------------
// The render block runs on the CoreAudio realtime thread. It allocates nothing,
// takes no lock, sends no Objective-C message and logs nothing: it drains a
// bounded lock-free command ring (producers serialise among themselves on a
// mutex the render thread never touches) into a fixed voice array it alone
// owns. Everything the app thread mutates — oscillator records, the AVAudioEngine
// graph — lives behind app-side mutexes the render thread never takes.
//
// Clicks
// ------
// Every note gets a ~2.5 ms attack ramp and a ~6 ms release ramp that starts at
// its scheduled stop time, so a burst of 24 ms notes (button-tetris) neither
// clicks on attack nor thuds on release.
//
// Verification hooks
// ------------------
// GEA_AUDIO_OFFLINE=1              build the graph in manual-rendering mode
//                                  (no output device is touched).
// GEA_AUDIO_CAPTURE_RAW=<path>     as above, plus a thread that pulls the graph
//                                  at real-time pace and appends raw interleaved
//                                  float32 stereo @48 kHz to <path>. That is how
//                                  a real app run is measured end-to-end —
//                                  analyze it with analyze-audio-capture.mjs.
// GEA_AUDIO_DISABLED=1             build no graph at all: the same state as
//                                  "no output device", everything still callable.
// GEA_AUDIO_DEBUG=1                one stderr line at setup: mode, rate, whether
//                                  the engine started, and why not.
// See apple_audio_testing.h for the in-process offline API, and
// build-audio-selftest.sh for the measurement harness.

#import <AVFoundation/AVFoundation.h>

#include <TargetConditionals.h>

#include "audio.h"

#include "apple_audio_testing.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace gea::platform::audio {

namespace {

constexpr int kMaxOscillators = 512;   // app-side handle pool (round-robin)
constexpr int kMaxVoices = 64;         // notes rendering simultaneously
constexpr int kCommandCapacity = 2048; // app thread -> render thread ring
constexpr double kTwoPi = 6.28318530717958647692;
constexpr double kDefaultFrequency = 440.0;
constexpr double kMinFrequency = 8.0;
constexpr double kMaxFrequency = 20000.0;
constexpr double kAttackSeconds = 0.0025;
constexpr double kReleaseSeconds = 0.006;
constexpr double kVoiceGain = 0.25;      // headroom: four notes at once still fit
constexpr double kMaxVoiceSeconds = 30.0; // a never-stopped note cannot run forever
constexpr double kFallbackSampleRate = 48000.0;
constexpr double kCaptureSampleRate = 48000.0;
constexpr AVAudioFrameCount kOfflineMaxFrames = 4096;
constexpr AVAudioFrameCount kCaptureBlockFrames = 512;

double steadySeconds()
{
	static const std::chrono::steady_clock::time_point origin = std::chrono::steady_clock::now();
	return std::chrono::duration<double>(std::chrono::steady_clock::now() - origin).count();
}

OscillatorType normalizeType(OscillatorType type)
{
	switch (type) {
	case OscillatorType::Sine:
	case OscillatorType::Square:
	case OscillatorType::Sawtooth:
	case OscillatorType::Triangle: return type;
	}
	return OscillatorType::Sine;
}

double normalizeFrequency(double frequency)
{
	if (!std::isfinite(frequency)) return kDefaultFrequency;
	if (frequency < kMinFrequency) return kMinFrequency;
	if (frequency > kMaxFrequency) return kMaxFrequency;
	return frequency;
}

// phase is [0, 1)
double waveform(OscillatorType type, double phase)
{
	switch (type) {
	case OscillatorType::Square: return phase < 0.5 ? 1.0 : -1.0;
	case OscillatorType::Sawtooth: return 2.0 * phase - 1.0;
	case OscillatorType::Triangle:
		if (phase < 0.25) return 4.0 * phase;
		if (phase < 0.75) return 2.0 - 4.0 * phase;
		return 4.0 * phase - 4.0;
	case OscillatorType::Sine: break;
	}
	return std::sin(phase * kTwoPi);
}

bool envFlagSet(const char *name)
{
	const char *value = std::getenv(name);
	return value != nullptr && value[0] != '\0' && std::strcmp(value, "0") != 0;
}

// ---------------------------------------------------------------------------
// app thread -> render thread commands
// ---------------------------------------------------------------------------
enum class CommandKind : std::uint8_t { StartVoice, StopVoice, SetFrequency, SetType, ScheduleFrequency };

struct Command {
	CommandKind kind = CommandKind::StartVoice;
	OscillatorType type = OscillatorType::Sine;
	std::uint64_t voice = 0;
	double frequency = kDefaultFrequency;
	std::int64_t frame = 0;
};

// Multi-producer (serialised by a mutex the consumer never takes), single
// consumer, wait-free on the consumer side.
class CommandQueue {
public:
	bool push(const Command &command)
	{
		std::lock_guard<std::mutex> guard(producers_);
		const std::uint32_t tail = tail_.load(std::memory_order_relaxed);
		const std::uint32_t next = (tail + 1u) % kCommandCapacity;
		if (next == head_.load(std::memory_order_acquire)) {
			dropped_.fetch_add(1, std::memory_order_relaxed);
			return false;
		}
		items_[tail] = command;
		tail_.store(next, std::memory_order_release);
		return true;
	}

	bool pop(Command &out)
	{
		const std::uint32_t head = head_.load(std::memory_order_relaxed);
		if (head == tail_.load(std::memory_order_acquire)) return false;
		out = items_[head];
		head_.store((head + 1u) % kCommandCapacity, std::memory_order_release);
		return true;
	}

	std::uint64_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

private:
	Command items_[kCommandCapacity]{};
	std::atomic<std::uint32_t> head_{0};
	std::atomic<std::uint32_t> tail_{0};
	std::atomic<std::uint64_t> dropped_{0};
	std::mutex producers_;
};

// ---------------------------------------------------------------------------
// render-thread voice state (touched by the render thread only)
// ---------------------------------------------------------------------------
constexpr int kMaxVoiceEvents = 8; // setValueAtTime events queued per note

struct VoiceEvent {
	std::int64_t frame = 0;
	double phaseIncrement = 0.0;
};

struct Voice {
	bool active = false;
	std::uint64_t id = 0;
	OscillatorType type = OscillatorType::Sine;
	double phase = 0.0;
	double phaseIncrement = 0.0;
	std::int64_t startFrame = 0;
	std::int64_t stopFrame = 0;
	std::int64_t endFrame = 0; // stopFrame + release, or the runaway cap
	bool stopScheduled = false;
	VoiceEvent events[kMaxVoiceEvents]{};
	int eventHead = 0;
	int eventCount = 0;
};

// ---------------------------------------------------------------------------
// app-thread oscillator records
// ---------------------------------------------------------------------------
struct ScheduledValue {
	double time = 0.0;
	double value = kDefaultFrequency;
};

struct OscillatorRecord {
	std::uint64_t handle = 0; // 0 == free slot
	OscillatorType type = OscillatorType::Sine;
	double frequency = kDefaultFrequency;
	bool connected = false;
	bool started = false;
	bool stopped = false;
	bool voiceLaunched = false;
	double startTime = 0.0;
	double stopTime = 0.0;
	// setValueAtTime() calls made before the note is handed to the render thread
	// are replayed as scheduled events the moment it is.
	ScheduledValue pending[kMaxVoiceEvents]{};
	int pendingCount = 0;
};

class Engine {
public:
	static Engine &instance()
	{
		// Deliberately leaked: a static destructor racing the CoreAudio render
		// thread at process exit is a crash nobody can debug, and the process is
		// going away anyway. The capture file (if any) is flushed per block.
		static Engine *engine = new Engine();
		return *engine;
	}

	// ---- timebase -----------------------------------------------------------
	double currentTime()
	{
		ensureSetup();
		if (!running_.load(std::memory_order_relaxed)) return steadySeconds();
		const double rate = sampleRate_.load(std::memory_order_relaxed);
		const std::int64_t frames =
		    frameOffset_.load(std::memory_order_relaxed) + renderedFrames_.load(std::memory_order_relaxed);
		return static_cast<double>(frames) / rate;
	}

	// ---- oscillator lifecycle ----------------------------------------------
	std::uint64_t createOscillator()
	{
		ensureSetup();
		std::lock_guard<std::mutex> guard(recordsMutex_);
		const int slot = nextSlot_;
		nextSlot_ = (nextSlot_ + 1) % kMaxOscillators;
		const std::uint64_t handle = (++generation_ << 10) | static_cast<std::uint64_t>(slot + 1);
		records_[slot] = OscillatorRecord{};
		records_[slot].handle = handle;
		return handle;
	}

	double frequency(std::uint64_t handle)
	{
		std::lock_guard<std::mutex> guard(recordsMutex_);
		const OscillatorRecord *record = find(handle);
		return record ? record->frequency : 0.0;
	}

	void setFrequency(std::uint64_t handle, double value)
	{
		Command command;
		bool live = false;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr || !std::isfinite(value)) return;
			record->frequency = value;
			live = record->voiceLaunched && !record->stopped;
			command = Command{CommandKind::SetFrequency, record->type, handle, normalizeFrequency(value), 0};
		}
		if (live) commands_.push(command);
	}

	OscillatorType type(std::uint64_t handle)
	{
		std::lock_guard<std::mutex> guard(recordsMutex_);
		const OscillatorRecord *record = find(handle);
		return record ? record->type : OscillatorType::Sine;
	}

	void setType(std::uint64_t handle, OscillatorType type)
	{
		Command command;
		bool live = false;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr) return;
			record->type = normalizeType(type);
			live = record->voiceLaunched && !record->stopped;
			command = Command{CommandKind::SetType, record->type, handle, record->frequency, 0};
		}
		if (live) commands_.push(command);
	}

	// A frequency change requested for a future time on a running note.
	void scheduleFrequency(std::uint64_t handle, double value, double time)
	{
		ensureSetup();
		Command command;
		bool emit = false;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr || !std::isfinite(value)) return;
			if (record->voiceLaunched && !record->stopped) {
				emit = true;
				command = Command{CommandKind::ScheduleFrequency, record->type, handle,
				                  normalizeFrequency(value), frameFor(time)};
			} else if (record->pendingCount < kMaxVoiceEvents) {
				record->pending[record->pendingCount++] = ScheduledValue{time, value};
			}
			// Web Audio: a value scheduled for the future does not change
			// frequency.value now — only setValue()/`= x` does that.
		}
		if (emit) commands_.push(command);
	}

	void connect(std::uint64_t handle)
	{
		Command commands[kMaxVoiceEvents + 2];
		int count = 0;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr || record->connected) return;
			record->connected = true;
			// start() before connect() is legal; the note becomes audible here.
			if (record->started && !record->voiceLaunched) {
				record->voiceLaunched = true;
				count = launchCommands(*record, handle, commands);
			}
		}
		for (int index = 0; index < count; ++index) commands_.push(commands[index]);
	}

	void start(std::uint64_t handle, double when)
	{
		ensureSetup();
		Command commands[kMaxVoiceEvents + 2];
		int count = 0;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr || record->started) return;
			record->started = true;
			const double now = currentTimeLocked();
			double at = (std::isfinite(when) && when > 0.0) ? when : now;
			if (at < now) at = now;
			record->startTime = at;
			if (record->connected) {
				record->voiceLaunched = true;
				count = launchCommands(*record, handle, commands);
			}
		}
		for (int index = 0; index < count; ++index) commands_.push(commands[index]);
	}

	void stop(std::uint64_t handle, double when)
	{
		ensureSetup();
		Command command;
		bool emit = false;
		{
			std::lock_guard<std::mutex> guard(recordsMutex_);
			OscillatorRecord *record = find(handle);
			if (record == nullptr || !record->started || record->stopped) return;
			record->stopped = true;
			const double now = currentTimeLocked();
			double at = (std::isfinite(when) && when > 0.0) ? when : now;
			if (at < record->startTime) at = record->startTime;
			record->stopTime = at;
			// stop() before connect() is legal too: the stop rides along with the
			// launch commands when connect() finally makes the note audible.
			emit = record->voiceLaunched;
			command = Command{CommandKind::StopVoice, record->type, handle, record->frequency, frameFor(at)};
		}
		if (emit) commands_.push(command);
	}

	// ---- volume -------------------------------------------------------------
	int volume() const { return volume_.load(std::memory_order_relaxed); }

	void setVolume(int percent)
	{
		if (percent < 0) percent = 0;
		if (percent > 100) percent = 100;
		volume_.store(percent, std::memory_order_relaxed);
		const float linear = static_cast<float>(percent) / 100.0f;
		std::lock_guard<std::mutex> guard(graphMutex_);
		@try {
			if (filePlayer_ != nil) filePlayer_.volume = linear;
			if (pcmPlayer_ != nil) pcmPlayer_.volume = linear;
		} @catch (NSException *exception) {
			(void)exception;
		}
	}

	// ---- sample playback ----------------------------------------------------
	bool playFile(const std::string &path)
	{
		ensureSetup();
		if (path.empty()) return false;
		NSURL *url = resolveURL(path);
		if (url == nil) return false;

		std::lock_guard<std::mutex> guard(graphMutex_);
		if (engine_ == nil) return false;
		@try {
			NSError *error = nil;
			AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
			if (file == nil) return false;
			if (filePlayer_ != nil) [filePlayer_ stop];
			if (!ensurePlayerLocked(filePlayer_, filePlayerFormat_, file.processingFormat)) return false;
			[filePlayer_ scheduleFile:file atTime:nil completionHandler:nil];
			[filePlayer_ play];
			return true;
		} @catch (NSException *exception) {
			(void)exception;
			return false;
		}
	}

	bool playPcm(const std::int16_t *samples, std::size_t sampleCount, int sampleRate, int channels)
	{
		ensureSetup();
		if (samples == nullptr || sampleCount == 0) return false;
		if (channels < 1) channels = 1;
		if (channels > 2) channels = 2;
		if (sampleRate <= 0) sampleRate = 16000;
		const std::size_t frames = sampleCount / static_cast<std::size_t>(channels);
		if (frames == 0) return false;

		std::lock_guard<std::mutex> guard(graphMutex_);
		if (engine_ == nil) return false;
		@try {
			AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
			                                                         sampleRate:static_cast<double>(sampleRate)
			                                                           channels:static_cast<AVAudioChannelCount>(channels)
			                                                        interleaved:NO];
			if (format == nil) return false;
			AVAudioPCMBuffer *buffer =
			    [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
			                                  frameCapacity:static_cast<AVAudioFrameCount>(frames)];
			if (buffer == nil) return false;
			buffer.frameLength = static_cast<AVAudioFrameCount>(frames);
			float *const *destination = buffer.floatChannelData;
			if (destination == nullptr) return false;
			for (std::size_t frame = 0; frame < frames; ++frame) {
				for (int channel = 0; channel < channels; ++channel) {
					const std::int16_t sample = samples[frame * static_cast<std::size_t>(channels) + channel];
					destination[channel][frame] = static_cast<float>(sample) / 32768.0f;
				}
			}
			if (pcmPlayer_ != nil) [pcmPlayer_ stop];
			if (!ensurePlayerLocked(pcmPlayer_, pcmPlayerFormat_, format)) return false;
			[pcmPlayer_ scheduleBuffer:buffer atTime:nil options:0 completionHandler:nil];
			[pcmPlayer_ play];
			return true;
		} @catch (NSException *exception) {
			(void)exception;
			return false;
		}
	}

	void stopPlayback()
	{
		std::lock_guard<std::mutex> guard(graphMutex_);
		@try {
			if (filePlayer_ != nil) [filePlayer_ stop];
			if (pcmPlayer_ != nil) [pcmPlayer_ stop];
		} @catch (NSException *exception) {
			(void)exception;
		}
	}

	// ---- offline rendering (see apple_audio_testing.h) -----------------------
	bool beginOffline(double sampleRate)
	{
		std::lock_guard<std::mutex> guard(graphMutex_);
		if (setupDone_) return false;
		offlineRequested_ = true;
		if (sampleRate > 0.0) offlineSampleRate_ = sampleRate;
		return true;
	}

	std::size_t renderOffline(float *interleavedStereo, std::size_t frames)
	{
		ensureSetup();
		std::lock_guard<std::mutex> guard(graphMutex_);
		return renderOfflineLocked(interleavedStereo, frames);
	}

	double offlineSampleRate() const { return sampleRate_.load(std::memory_order_relaxed); }

	void endOffline()
	{
		std::lock_guard<std::mutex> guard(graphMutex_);
		if (engine_ == nil) return;
		@try {
			[engine_ stop];
			if (engine_.isInManualRenderingMode) [engine_ disableManualRenderingMode];
		} @catch (NSException *exception) {
			(void)exception;
		}
		running_.store(false, std::memory_order_relaxed);
	}

	// ---- realtime render callback ------------------------------------------
	// Realtime thread. No allocation, no lock, no Objective-C, no logging.
	void renderAudio(AVAudioFrameCount frameCount, AudioBufferList *output, BOOL *isSilence)
	{
		Command command;
		while (commands_.pop(command)) applyCommand(command);

		const std::int64_t base =
		    frameOffset_.load(std::memory_order_relaxed) + renderedFrames_.load(std::memory_order_relaxed);
		const double gain =
		    static_cast<double>(volume_.load(std::memory_order_relaxed)) / 100.0 * kVoiceGain;
		const double attack = attackFrames_;
		const double release = releaseFrames_;

		bool sounded = false;
		const std::uint32_t bufferCount = output != nullptr ? output->mNumberBuffers : 0;
		float *channel0 = bufferCount > 0 ? static_cast<float *>(output->mBuffers[0].mData) : nullptr;
		float *channel1 = bufferCount > 1 ? static_cast<float *>(output->mBuffers[1].mData) : nullptr;

		for (AVAudioFrameCount index = 0; index < frameCount; ++index) {
			const std::int64_t frame = base + static_cast<std::int64_t>(index);
			double mixed = 0.0;
			for (Voice &voice : voices_) {
				if (!voice.active) continue;
				if (frame >= voice.endFrame) {
					voice.active = false;
					continue;
				}
				if (frame < voice.startFrame) continue;

				while (voice.eventCount > 0 && frame >= voice.events[voice.eventHead].frame) {
					voice.phaseIncrement = voice.events[voice.eventHead].phaseIncrement;
					voice.eventHead = (voice.eventHead + 1) % kMaxVoiceEvents;
					--voice.eventCount;
				}

				double level = 1.0;
				const double sinceStart = static_cast<double>(frame - voice.startFrame);
				if (sinceStart < attack) level = sinceStart / attack;
				if (voice.stopScheduled && frame >= voice.stopFrame) {
					const double sinceStop = static_cast<double>(frame - voice.stopFrame);
					const double decay = 1.0 - sinceStop / release;
					level *= decay > 0.0 ? decay : 0.0;
				}

				mixed += waveform(voice.type, voice.phase) * level;
				voice.phase += voice.phaseIncrement;
				if (voice.phase >= 1.0) voice.phase -= 1.0;
				sounded = true;
			}

			double sample = mixed * gain;
			if (sample > 1.0) sample = 1.0;
			if (sample < -1.0) sample = -1.0;
			const float value = static_cast<float>(sample);
			if (channel0 != nullptr) channel0[index] = value;
			if (channel1 != nullptr) channel1[index] = value;
		}

		for (std::uint32_t buffer = 2; buffer < bufferCount; ++buffer) {
			float *extra = static_cast<float *>(output->mBuffers[buffer].mData);
			if (extra == nullptr) continue;
			for (AVAudioFrameCount index = 0; index < frameCount; ++index) extra[index] = 0.0f;
		}

		renderedFrames_.fetch_add(static_cast<std::int64_t>(frameCount), std::memory_order_relaxed);
		if (isSilence != nullptr) *isSilence = sounded ? NO : YES;
	}

private:
	Engine() = default;

	// ---- records ------------------------------------------------------------
	OscillatorRecord *find(std::uint64_t handle)
	{
		if (handle == 0) return nullptr;
		const std::uint64_t slot = (handle & 0x3ffull);
		if (slot == 0 || slot > static_cast<std::uint64_t>(kMaxOscillators)) return nullptr;
		OscillatorRecord &record = records_[slot - 1];
		return record.handle == handle ? &record : nullptr;
	}

	const OscillatorRecord *find(std::uint64_t handle) const
	{
		return const_cast<Engine *>(this)->find(handle);
	}

	// The StartVoice command plus any setValueAtTime events queued before launch.
	int launchCommands(const OscillatorRecord &record, std::uint64_t handle, Command *out) const
	{
		double initial = record.frequency;
		int count = 0;
		// An event at or before the note's start time is just the starting value.
		for (int index = 0; index < record.pendingCount; ++index) {
			if (record.pending[index].time <= record.startTime) initial = record.pending[index].value;
		}
		out[count++] = Command{CommandKind::StartVoice, record.type, handle, normalizeFrequency(initial),
		                       frameFor(record.startTime)};
		for (int index = 0; index < record.pendingCount; ++index) {
			const ScheduledValue &event = record.pending[index];
			if (event.time <= record.startTime) continue;
			out[count++] = Command{CommandKind::ScheduleFrequency, record.type, handle,
			                       normalizeFrequency(event.value), frameFor(event.time)};
		}
		if (record.stopped) {
			out[count++] = Command{CommandKind::StopVoice, record.type, handle,
			                       normalizeFrequency(record.frequency), frameFor(record.stopTime)};
		}
		return count;
	}

	// currentTime() without ensureSetup() — callable while recordsMutex_ is held.
	double currentTimeLocked() const
	{
		if (!running_.load(std::memory_order_relaxed)) return steadySeconds();
		const double rate = sampleRate_.load(std::memory_order_relaxed);
		const std::int64_t frames =
		    frameOffset_.load(std::memory_order_relaxed) + renderedFrames_.load(std::memory_order_relaxed);
		return static_cast<double>(frames) / rate;
	}

	std::int64_t frameFor(double seconds) const
	{
		const double rate = sampleRate_.load(std::memory_order_relaxed);
		const double frame = seconds * rate;
		if (!std::isfinite(frame)) return 0;
		if (frame > 9.0e15) return static_cast<std::int64_t>(9.0e15);
		if (frame < 0.0) return 0;
		return static_cast<std::int64_t>(std::llround(frame));
	}

	// ---- render-thread command application ----------------------------------
	void applyCommand(const Command &command)
	{
		switch (command.kind) {
		case CommandKind::StartVoice: {
			Voice *voice = allocateVoice();
			if (voice == nullptr) return;
			const double rate = sampleRate_.load(std::memory_order_relaxed);
			voice->active = true;
			voice->id = command.voice;
			voice->type = command.type;
			voice->phase = 0.0;
			voice->phaseIncrement = command.frequency / rate;
			voice->startFrame = command.frame;
			voice->stopFrame = 0;
			voice->stopScheduled = false;
			voice->endFrame = command.frame + static_cast<std::int64_t>(kMaxVoiceSeconds * rate);
			voice->eventHead = 0;
			voice->eventCount = 0;
			return;
		}
		case CommandKind::StopVoice: {
			Voice *voice = findVoice(command.voice);
			if (voice == nullptr) return;
			std::int64_t at = command.frame;
			if (at < voice->startFrame) at = voice->startFrame;
			voice->stopFrame = at;
			voice->stopScheduled = true;
			voice->endFrame = at + static_cast<std::int64_t>(releaseFrames_) + 1;
			return;
		}
		case CommandKind::SetFrequency: {
			Voice *voice = findVoice(command.voice);
			if (voice == nullptr) return;
			voice->phaseIncrement = command.frequency / sampleRate_.load(std::memory_order_relaxed);
			return;
		}
		case CommandKind::SetType: {
			Voice *voice = findVoice(command.voice);
			if (voice == nullptr) return;
			voice->type = command.type;
			return;
		}
		case CommandKind::ScheduleFrequency: {
			Voice *voice = findVoice(command.voice);
			if (voice == nullptr || voice->eventCount >= kMaxVoiceEvents) return;
			const int slot = (voice->eventHead + voice->eventCount) % kMaxVoiceEvents;
			voice->events[slot] =
			    VoiceEvent{command.frame, command.frequency / sampleRate_.load(std::memory_order_relaxed)};
			++voice->eventCount;
			return;
		}
		}
	}

	Voice *findVoice(std::uint64_t id)
	{
		for (Voice &voice : voices_)
			if (voice.active && voice.id == id) return &voice;
		return nullptr;
	}

	Voice *allocateVoice()
	{
		Voice *oldest = nullptr;
		for (Voice &voice : voices_) {
			if (!voice.active) return &voice;
			if (oldest == nullptr || voice.endFrame < oldest->endFrame) oldest = &voice;
		}
		return oldest; // steal the note closest to finishing
	}

	// ---- engine setup -------------------------------------------------------
	void ensureSetup()
	{
		if (setupDone_.load(std::memory_order_acquire)) return;
		std::lock_guard<std::mutex> guard(graphMutex_);
		if (setupDone_.load(std::memory_order_relaxed)) return;
		setupLocked();
		setupDone_.store(true, std::memory_order_release);
	}

	void setupLocked()
	{
		const bool offline = offlineRequested_ || envFlagSet("GEA_AUDIO_OFFLINE") ||
		                     (std::getenv("GEA_AUDIO_CAPTURE_RAW") != nullptr);
		const char *capturePath = std::getenv("GEA_AUDIO_CAPTURE_RAW");

		// GEA_AUDIO_DISABLED=1 builds no graph at all. That is the same state the
		// backend lands in when there is no output device, so it is also how the
		// no-device path is exercised: everything stays callable, currentTime()
		// runs off the wall clock and nothing sounds.
		if (envFlagSet("GEA_AUDIO_DISABLED")) {
			running_.store(false, std::memory_order_relaxed);
			report(offline, sampleRate_.load(std::memory_order_relaxed), false, nil);
			return;
		}

		@try {
#if TARGET_OS_IPHONE
			if (!offline) activateAudioSession();
#endif
			engine_ = [[AVAudioEngine alloc] init];
			if (engine_ == nil) return;

			double rate = kFallbackSampleRate;
			if (offline) {
				rate = capturePath != nullptr ? kCaptureSampleRate : offlineSampleRate_;
			} else {
				const double deviceRate = [[engine_ outputNode] outputFormatForBus:0].sampleRate;
				if (deviceRate > 0.0) rate = deviceRate;
			}
			if (!(rate > 0.0)) rate = kFallbackSampleRate;
			sampleRate_.store(rate, std::memory_order_relaxed);
			attackFrames_ = std::max(1.0, kAttackSeconds * rate);
			releaseFrames_ = std::max(1.0, kReleaseSeconds * rate);

			format_ = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
			                                           sampleRate:rate
			                                             channels:2
			                                          interleaved:NO];
			if (format_ == nil) return;

			Engine *self = this;
			sourceNode_ = [[AVAudioSourceNode alloc]
			    initWithFormat:format_
			       renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp,
			                             AVAudioFrameCount frameCount, AudioBufferList *outputData) {
				       (void)timestamp;
				       self->renderAudio(frameCount, outputData, isSilence);
				       return noErr;
			       }];
			if (sourceNode_ == nil) return;

			[engine_ attachNode:sourceNode_];
			[engine_ connect:sourceNode_ to:[engine_ mainMixerNode] format:format_];

			if (offline) {
				NSError *error = nil;
				if (![engine_ enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
				                                 format:format_
				                      maximumFrameCount:kOfflineMaxFrames
				                                  error:&error]) {
					return;
				}
				manualBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine_.manualRenderingFormat
				                                             frameCapacity:kOfflineMaxFrames];
				if (manualBuffer_ == nil) return;
			}

			const double rateNow = sampleRate_.load(std::memory_order_relaxed);
			renderedFrames_.store(0, std::memory_order_relaxed);
			frameOffset_.store(static_cast<std::int64_t>(std::llround(steadySeconds() * rateNow)),
			                   std::memory_order_relaxed);

			NSError *startError = nil;
			if (![engine_ startAndReturnError:&startError]) {
				running_.store(false, std::memory_order_relaxed);
				// No output device (or the device refused): stay silent, keep the
				// wall-clock timebase, and retry when the configuration changes.
				report(offline, rateNow, false, startError);
				observeConfigurationChanges();
				return;
			}
			running_.store(true, std::memory_order_relaxed);
			report(offline, rateNow, true, nil);
			offlineMode_ = offline;
			const float linear = static_cast<float>(volume_.load(std::memory_order_relaxed)) / 100.0f;
			if (filePlayer_ != nil) filePlayer_.volume = linear;
			if (pcmPlayer_ != nil) pcmPlayer_.volume = linear;
			if (!offline) observeConfigurationChanges();
			if (capturePath != nullptr) startCaptureLocked(capturePath);
		} @catch (NSException *exception) {
			(void)exception;
			running_.store(false, std::memory_order_relaxed);
		}
	}

	// GEA_AUDIO_DEBUG=1 prints one line at setup. Never called from the render
	// thread, so stdio here is safe.
	void report(bool offline, double rate, bool started, NSError *error) const
	{
		if (!envFlagSet("GEA_AUDIO_DEBUG")) return;
		const char *reason = error != nil ? error.localizedDescription.UTF8String : "";
		std::fprintf(stderr, "[gea-audio] mode=%s rate=%.0f started=%s%s%s\n",
		             offline ? "offline" : "device", rate, started ? "yes" : "no",
		             started ? "" : " error=", reason != nullptr ? reason : "");
		std::fflush(stderr);
	}

#if TARGET_OS_IPHONE
	void activateAudioSession()
	{
		@try {
			AVAudioSession *session = [AVAudioSession sharedInstance];
			NSError *error = nil;
			// Playback (not Ambient) so a game's sound is audible with the ring
			// switch silenced; MixWithOthers so it does not stop the user's music.
			[session setCategory:AVAudioSessionCategoryPlayback
			         withOptions:AVAudioSessionCategoryOptionMixWithOthers
			               error:&error];
			[session setActive:YES error:&error];
		} @catch (NSException *exception) {
			(void)exception;
		}
		observeInterruptions();
	}

	// A call or Siri deactivates the session and stops the engine; nothing
	// restarts it on its own. Reactivate and restart when the interruption ends.
	void observeInterruptions()
	{
		if (interruptionObserver_ != nil) return;
		Engine *self = this;
		interruptionObserver_ = [[NSNotificationCenter defaultCenter]
		    addObserverForName:AVAudioSessionInterruptionNotification
		                object:[AVAudioSession sharedInstance]
		                 queue:nil
		            usingBlock:^(NSNotification *note) {
			            NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
			            if (type == nil ||
			                type.unsignedIntegerValue != AVAudioSessionInterruptionTypeEnded) {
				            self->markStopped();
				            return;
			            }
			            self->activateAudioSession();
			            self->handleConfigurationChange();
		            }];
	}
#endif

	void markStopped() { running_.store(false, std::memory_order_relaxed); }

	// A device disappearing (unplugged headphones, a display with speakers going
	// away) stops the engine; AVAudioEngine posts a configuration change and the
	// graph must be restarted. This also recovers a launch with no output device.
	void observeConfigurationChanges()
	{
		if (configurationObserver_ != nil) return;
		Engine *self = this;
		configurationObserver_ = [[NSNotificationCenter defaultCenter]
		    addObserverForName:AVAudioEngineConfigurationChangeNotification
		                object:engine_
		                 queue:nil
		            usingBlock:^(NSNotification *note) {
			            (void)note;
			            self->handleConfigurationChange();
		            }];
	}

	void handleConfigurationChange()
	{
		std::lock_guard<std::mutex> guard(graphMutex_);
		if (engine_ == nil || offlineMode_) return;
		@try {
			if (engine_.isRunning) return;
			const double rate = sampleRate_.load(std::memory_order_relaxed);
			renderedFrames_.store(0, std::memory_order_relaxed);
			frameOffset_.store(static_cast<std::int64_t>(std::llround(steadySeconds() * rate)),
			                   std::memory_order_relaxed);
			NSError *error = nil;
			running_.store([engine_ startAndReturnError:&error] ? true : false, std::memory_order_relaxed);
		} @catch (NSException *exception) {
			(void)exception;
			running_.store(false, std::memory_order_relaxed);
		}
	}

	bool ensurePlayerLocked(AVAudioPlayerNode *__strong &player, AVAudioFormat *__strong &current,
	                        AVAudioFormat *wanted)
	{
		if (engine_ == nil || wanted == nil) return false;
		if (player == nil) {
			player = [[AVAudioPlayerNode alloc] init];
			if (player == nil) return false;
			[engine_ attachNode:player];
			player.volume = static_cast<float>(volume_.load(std::memory_order_relaxed)) / 100.0f;
		}
		if (current == nil || ![current isEqual:wanted]) {
			[engine_ disconnectNodeOutput:player];
			[engine_ connect:player to:[engine_ mainMixerNode] format:wanted];
			current = wanted;
		}
		if (!engine_.isRunning) {
			NSError *error = nil;
			if (![engine_ startAndReturnError:&error]) return false;
			running_.store(true, std::memory_order_relaxed);
		}
		return true;
	}

	NSURL *resolveURL(const std::string &path) const
	{
		NSString *text = [NSString stringWithUTF8String:path.c_str()];
		if (text == nil || text.length == 0) return nil;
		if ([text hasPrefix:@"file://"] || [text hasPrefix:@"http://"] || [text hasPrefix:@"https://"]) {
			return [NSURL URLWithString:text];
		}
		if ([text hasPrefix:@"/"]) return [NSURL fileURLWithPath:text];

		NSString *stripped = [text hasPrefix:@"./"] ? [text substringFromIndex:2] : text;
		NSBundle *bundle = [NSBundle mainBundle];
		if (bundle != nil) {
			NSString *name = [stripped stringByDeletingPathExtension];
			NSString *extension = [stripped pathExtension];
			NSURL *resource = [bundle URLForResource:name withExtension:extension];
			if (resource != nil) return resource;
			NSString *inResources = [[bundle resourcePath] stringByAppendingPathComponent:stripped];
			if (inResources != nil && [[NSFileManager defaultManager] fileExistsAtPath:inResources]) {
				return [NSURL fileURLWithPath:inResources];
			}
		}
		return [NSURL fileURLWithPath:stripped];
	}

	std::size_t renderOfflineLocked(float *interleavedStereo, std::size_t frames)
	{
		if (engine_ == nil || manualBuffer_ == nil || !engine_.isInManualRenderingMode) return 0;
		std::size_t done = 0;
		@try {
			while (done < frames) {
				const AVAudioFrameCount want = static_cast<AVAudioFrameCount>(
				    std::min<std::size_t>(frames - done, kOfflineMaxFrames));
				NSError *error = nil;
				const AVAudioEngineManualRenderingStatus status =
				    [engine_ renderOffline:want toBuffer:manualBuffer_ error:&error];
				if (status != AVAudioEngineManualRenderingStatusSuccess) break;
				const AVAudioFrameCount produced = manualBuffer_.frameLength;
				if (produced == 0) break;
				float *const *channels = manualBuffer_.floatChannelData;
				const AVAudioChannelCount channelCount = manualBuffer_.format.channelCount;
				if (interleavedStereo != nullptr && channels != nullptr) {
					for (AVAudioFrameCount frame = 0; frame < produced; ++frame) {
						const float left = channels[0][frame];
						const float right = channelCount > 1 ? channels[1][frame] : left;
						interleavedStereo[(done + frame) * 2 + 0] = left;
						interleavedStereo[(done + frame) * 2 + 1] = right;
					}
				}
				done += produced;
				if (produced < want) break;
			}
		} @catch (NSException *exception) {
			(void)exception;
		}
		return done;
	}

	// Real-time-paced offline capture: renders the graph exactly as the device
	// would consume it and appends raw interleaved float32 stereo to a file.
	void startCaptureLocked(const char *path)
	{
		captureFile_ = std::fopen(path, "wb");
		if (captureFile_ == nullptr) return;
		captureRunning_.store(true, std::memory_order_relaxed);
		Engine *self = this;
		std::thread([self] { self->captureLoop(); }).detach();
	}

	void captureLoop()
	{
		std::vector<float> block(static_cast<std::size_t>(kCaptureBlockFrames) * 2, 0.0f);
		const double rate = sampleRate_.load(std::memory_order_relaxed);
		const double blockSeconds = static_cast<double>(kCaptureBlockFrames) / rate;
		auto deadline = std::chrono::steady_clock::now();
		while (captureRunning_.load(std::memory_order_relaxed)) {
			std::size_t produced = 0;
			{
				std::lock_guard<std::mutex> guard(graphMutex_);
				produced = renderOfflineLocked(block.data(), kCaptureBlockFrames);
			}
			if (produced > 0 && captureFile_ != nullptr) {
				std::fwrite(block.data(), sizeof(float), produced * 2, captureFile_);
				std::fflush(captureFile_);
			}
			deadline += std::chrono::duration_cast<std::chrono::steady_clock::duration>(
			    std::chrono::duration<double>(blockSeconds));
			std::this_thread::sleep_until(deadline);
		}
	}

	// ---- state --------------------------------------------------------------
	std::mutex graphMutex_;
	std::mutex recordsMutex_;
	CommandQueue commands_;

	OscillatorRecord records_[kMaxOscillators]{};
	int nextSlot_ = 0;
	std::uint64_t generation_ = 0;

	Voice voices_[kMaxVoices]{};

	std::atomic<bool> setupDone_{false};
	std::atomic<bool> running_{false};
	std::atomic<double> sampleRate_{kFallbackSampleRate};
	std::atomic<std::int64_t> renderedFrames_{0};
	std::atomic<std::int64_t> frameOffset_{0};
	std::atomic<int> volume_{80};
	double attackFrames_ = kAttackSeconds * kFallbackSampleRate;
	double releaseFrames_ = kReleaseSeconds * kFallbackSampleRate;

	bool offlineRequested_ = false;
	bool offlineMode_ = false;
	double offlineSampleRate_ = kFallbackSampleRate;

	std::atomic<bool> captureRunning_{false};
	std::FILE *captureFile_ = nullptr;

	AVAudioEngine *engine_ = nil;
	AVAudioSourceNode *sourceNode_ = nil;
	AVAudioFormat *format_ = nil;
	AVAudioPCMBuffer *manualBuffer_ = nil;
	AVAudioPlayerNode *filePlayer_ = nil;
	AVAudioFormat *filePlayerFormat_ = nil;
	AVAudioPlayerNode *pcmPlayer_ = nil;
	AVAudioFormat *pcmPlayerFormat_ = nil;
	id configurationObserver_ = nil;
	id interruptionObserver_ = nil;
};

}  // namespace

// ---------------------------------------------------------------------------
// gea::platform::audio public API
// ---------------------------------------------------------------------------

AudioParam::AudioParam(NativeAudioHandle oscillator) : oscillator_(oscillator) {}

double AudioParam::value() const
{
	return Engine::instance().frequency(static_cast<std::uint64_t>(oscillator_));
}

void AudioParam::setValue(double value)
{
	Engine::instance().setFrequency(static_cast<std::uint64_t>(oscillator_), value);
}

void AudioParam::setValueAtTime(double value, double start_time)
{
	// The engine schedules a note's parameters at start; a change requested for a
	// future time on an already-running note is applied when that time arrives.
	Engine &engine = Engine::instance();
	const auto handle = static_cast<std::uint64_t>(oscillator_);
	if (!std::isfinite(start_time) || start_time <= engine.currentTime()) {
		engine.setFrequency(handle, value);
		return;
	}
	engine.scheduleFrequency(handle, value, start_time);
}

AudioNode::AudioNode(NativeAudioHandle native) : native_(native) {}

NativeAudioHandle AudioNode::nativeId() const { return native_; }

AudioDestinationNode::AudioDestinationNode(NativeAudioHandle native) : AudioNode(native) {}

OscillatorNode::OscillatorNode(NativeAudioHandle native) : AudioNode(native), frequency(native) {}

OscillatorType OscillatorNode::type() const
{
	return Engine::instance().type(static_cast<std::uint64_t>(nativeId()));
}

void OscillatorNode::setType(OscillatorType type)
{
	Engine::instance().setType(static_cast<std::uint64_t>(nativeId()), type);
}

void OscillatorNode::connect(const AudioDestinationNode &)
{
	Engine::instance().connect(static_cast<std::uint64_t>(nativeId()));
}

void OscillatorNode::start(double when)
{
	Engine::instance().start(static_cast<std::uint64_t>(nativeId()), when);
}

void OscillatorNode::stop(double when)
{
	Engine::instance().stop(static_cast<std::uint64_t>(nativeId()), when);
}

double AudioContext::currentTime() const { return Engine::instance().currentTime(); }

AudioDestinationNode AudioContext::destination() const { return AudioDestinationNode(1); }

OscillatorNode AudioContext::createOscillator() const
{
	return OscillatorNode(static_cast<NativeAudioHandle>(Engine::instance().createOscillator()));
}

AudioContext AudioSystem::sharedContext() { return AudioContext{}; }

int AudioSystem::volume() { return Engine::instance().volume(); }

void AudioSystem::setVolume(int volume_percent) { Engine::instance().setVolume(volume_percent); }

bool AudioSystem::playFile(const std::string &path) { return Engine::instance().playFile(path); }

bool AudioSystem::playPcm(const std::int16_t *samples, std::size_t sample_count, int sample_rate, int channels)
{
	return Engine::instance().playPcm(samples, sample_count, sample_rate, channels);
}

void AudioSystem::stopPlayback() { Engine::instance().stopPlayback(); }

namespace testing {

bool beginOfflineRendering(double sample_rate) { return Engine::instance().beginOffline(sample_rate); }

std::size_t renderOfflineFrames(float *interleaved_stereo, std::size_t frames)
{
	return Engine::instance().renderOffline(interleaved_stereo, frames);
}

double offlineSampleRate() { return Engine::instance().offlineSampleRate(); }

void endOfflineRendering() { Engine::instance().endOffline(); }

}  // namespace testing

}  // namespace gea::platform::audio

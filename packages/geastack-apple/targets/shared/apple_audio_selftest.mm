// SPDX-License-Identifier: Apache-2.0
//
// Measures the Apple audio backend (targets/shared/apple_audio.mm) instead of
// trusting that it links. It drives the real gea::platform::audio API — the same
// calls button-tetris makes — through AVAudioEngine's manual-rendering mode and
// checks the rendered samples: RMS while a note is scheduled, silence when none
// is, the measured fundamental against the requested frequency, mixing,
// scheduling, volume, click-freedom and PCM/file playback.
//
// Build and run: targets/shared/build-audio-selftest.sh

#include "audio.h"

#include "apple_audio_testing.h"

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <atomic>
#include <ctime>
#include <string>
#include <thread>
#include <vector>

namespace audio = gea::platform::audio;

namespace {

constexpr double kSampleRate = 48000.0;

int g_failures = 0;
int g_checks = 0;

void check(bool ok, const char *label, const char *detail)
{
	++g_checks;
	if (!ok) ++g_failures;
	std::printf("  [%s] %-46s %s\n", ok ? "PASS" : "FAIL", label, detail);
}

std::string format(const char *fmt, ...)
{
	char buffer[256];
	va_list args;
	va_start(args, fmt);
	std::vsnprintf(buffer, sizeof buffer, fmt, args);
	va_end(args);
	return std::string(buffer);
}

struct Capture {
	std::vector<float> interleaved; // stereo
	double sampleRate = kSampleRate;

	std::size_t frames() const { return interleaved.size() / 2; }
	float left(std::size_t frame) const { return interleaved[frame * 2]; }
	std::size_t frameAt(double seconds) const
	{
		const double frame = seconds * sampleRate;
		if (frame < 0.0) return 0;
		const auto index = static_cast<std::size_t>(frame);
		return index > frames() ? frames() : index;
	}
};

Capture render(double seconds)
{
	Capture capture;
	capture.sampleRate = audio::testing::offlineSampleRate();
	const auto want = static_cast<std::size_t>(seconds * capture.sampleRate);
	capture.interleaved.assign(want * 2, 0.0f);
	const std::size_t produced = audio::testing::renderOfflineFrames(capture.interleaved.data(), want);
	capture.interleaved.resize(produced * 2);
	return capture;
}

double rms(const Capture &capture, double fromSeconds, double toSeconds)
{
	const std::size_t from = capture.frameAt(fromSeconds);
	const std::size_t to = capture.frameAt(toSeconds);
	if (to <= from) return 0.0;
	double sum = 0.0;
	for (std::size_t frame = from; frame < to; ++frame) {
		const double sample = capture.left(frame);
		sum += sample * sample;
	}
	return std::sqrt(sum / static_cast<double>(to - from));
}

double peak(const Capture &capture, double fromSeconds, double toSeconds)
{
	const std::size_t from = capture.frameAt(fromSeconds);
	const std::size_t to = capture.frameAt(toSeconds);
	double worst = 0.0;
	for (std::size_t frame = from; frame < to; ++frame) worst = std::fmax(worst, std::fabs(capture.left(frame)));
	return worst;
}

// Fundamental from zero crossings of the DC-removed signal. Exact enough for the
// clean single tones the synth produces (square, sine, triangle, sawtooth).
double measuredFrequency(const Capture &capture, double fromSeconds, double toSeconds)
{
	const std::size_t from = capture.frameAt(fromSeconds);
	const std::size_t to = capture.frameAt(toSeconds);
	if (to - from < 16) return 0.0;

	double mean = 0.0;
	for (std::size_t frame = from; frame < to; ++frame) mean += capture.left(frame);
	mean /= static_cast<double>(to - from);

	const double threshold = 0.05 * peak(capture, fromSeconds, toSeconds);
	int crossings = 0;
	int sign = 0;
	std::size_t firstCrossing = 0;
	std::size_t lastCrossing = 0;
	for (std::size_t frame = from; frame < to; ++frame) {
		const double value = capture.left(frame) - mean;
		int next = sign;
		if (value > threshold) next = 1;
		else if (value < -threshold) next = -1;
		if (next != sign && sign != 0) {
			if (crossings == 0) firstCrossing = frame;
			lastCrossing = frame;
			++crossings;
		}
		sign = next;
	}
	if (crossings < 2 || lastCrossing <= firstCrossing) return 0.0;
	const double span = static_cast<double>(lastCrossing - firstCrossing) / capture.sampleRate;
	return static_cast<double>(crossings - 1) / (2.0 * span);
}

// Energy at one frequency (Goertzel-style correlation), used to prove that a mix
// really contains every requested partial.
double energyAt(const Capture &capture, double frequency, double fromSeconds, double toSeconds)
{
	const std::size_t from = capture.frameAt(fromSeconds);
	const std::size_t to = capture.frameAt(toSeconds);
	if (to <= from) return 0.0;
	double real = 0.0;
	double imaginary = 0.0;
	const double step = 2.0 * M_PI * frequency / capture.sampleRate;
	for (std::size_t frame = from; frame < to; ++frame) {
		const double phase = step * static_cast<double>(frame - from);
		const double sample = capture.left(frame);
		real += sample * std::cos(phase);
		imaginary += sample * std::sin(phase);
	}
	const double count = static_cast<double>(to - from);
	return 2.0 * std::sqrt(real * real + imaginary * imaginary) / count;
}

double maxDelta(const Capture &capture, double fromSeconds, double toSeconds)
{
	const std::size_t from = capture.frameAt(fromSeconds);
	const std::size_t to = capture.frameAt(toSeconds);
	double worst = 0.0;
	for (std::size_t frame = from + 1; frame < to; ++frame) {
		worst = std::fmax(worst, std::fabs(capture.left(frame) - capture.left(frame - 1)));
	}
	return worst;
}

audio::OscillatorNode note(double frequency, audio::OscillatorType type, double start, double stop)
{
	audio::AudioContext context = audio::AudioSystem::sharedContext();
	audio::OscillatorNode oscillator = context.createOscillator();
	oscillator.setType(type);
	oscillator.frequency.setValue(frequency);
	oscillator.connect(context.destination());
	oscillator.start(start);
	oscillator.stop(stop);
	return oscillator;
}

std::string writeTestWav(double frequency, double seconds, int sampleRate)
{
	const char *tmp = std::getenv("TMPDIR");
	std::string path = (tmp != nullptr && tmp[0] != '\0') ? tmp : "/var/tmp";
	if (path.back() != '/') path.push_back('/');
	path += "gea-apple-audio-selftest.wav";

	const int frames = static_cast<int>(seconds * sampleRate);
	std::vector<std::int16_t> samples(static_cast<std::size_t>(frames));
	for (int frame = 0; frame < frames; ++frame) {
		const double phase = 2.0 * M_PI * frequency * static_cast<double>(frame) / sampleRate;
		samples[static_cast<std::size_t>(frame)] = static_cast<std::int16_t>(std::sin(phase) * 12000.0);
	}

	std::FILE *file = std::fopen(path.c_str(), "wb");
	if (file == nullptr) return std::string();
	const std::uint32_t dataBytes = static_cast<std::uint32_t>(samples.size() * sizeof(std::int16_t));
	const std::uint32_t riffSize = 36u + dataBytes;
	const std::uint32_t rate = static_cast<std::uint32_t>(sampleRate);
	const std::uint32_t byteRate = rate * 2u;
	const std::uint16_t one = 1;
	const std::uint16_t bits = 16;
	const std::uint16_t blockAlign = 2;
	const std::uint32_t fmtSize = 16;
	std::fwrite("RIFF", 1, 4, file);
	std::fwrite(&riffSize, 4, 1, file);
	std::fwrite("WAVEfmt ", 1, 8, file);
	std::fwrite(&fmtSize, 4, 1, file);
	std::fwrite(&one, 2, 1, file);       // PCM
	std::fwrite(&one, 2, 1, file);       // mono
	std::fwrite(&rate, 4, 1, file);
	std::fwrite(&byteRate, 4, 1, file);
	std::fwrite(&blockAlign, 2, 1, file);
	std::fwrite(&bits, 2, 1, file);
	std::fwrite("data", 1, 4, file);
	std::fwrite(&dataBytes, 4, 1, file);
	std::fwrite(samples.data(), sizeof(std::int16_t), samples.size(), file);
	std::fclose(file);
	return path;
}

}  // namespace

// GEA_AUDIO_DISABLED=1 puts the backend in exactly the state it reaches when no
// output device is available: no graph, nothing sounding. Everything must still
// be callable, and the clock must still advance so an app whose scheduler reads
// currentTime() keeps making progress instead of wedging.
int runNoDeviceChecks()
{
	std::printf("no-device path (GEA_AUDIO_DISABLED=1)\n");
	audio::AudioContext context = audio::AudioSystem::sharedContext();
	const double t0 = context.currentTime();

	audio::OscillatorNode oscillator = context.createOscillator();
	oscillator.setType(audio::OscillatorType::Square);
	oscillator.frequency.setValue(440.0);
	oscillator.connect(context.destination());
	oscillator.start(t0 + 0.01);
	oscillator.stop(t0 + 0.05);

	check(static_cast<double>(oscillator.frequency.value()) == 440.0, "frequency still reads back", "440");
	check(oscillator.type() == audio::OscillatorType::Square, "type still reads back", "Square");

	// A never-drained command ring must not grow or trip: hammer it well past
	// its capacity (this also recycles the oscillator pool many times over).
	for (int index = 0; index < 5000; ++index) {
		audio::OscillatorNode extra = context.createOscillator();
		extra.setType(audio::OscillatorType::Sine);
		extra.frequency.setValue(200.0 + index);
		extra.connect(context.destination());
		extra.start(t0);
		extra.stop(t0 + 0.01);
	}
	audio::OscillatorNode fresh = context.createOscillator();
	fresh.frequency.setValue(123.0);
	check(static_cast<double>(fresh.frequency.value()) == 123.0, "still usable after 5000 oscillators", "123");

	struct timespec pause = {0, 30 * 1000 * 1000};
	nanosleep(&pause, nullptr);
	const double t1 = context.currentTime();
	check(t1 > t0, "currentTime() still advances (wall clock)", format("%.4f -> %.4f", t0, t1).c_str());

	const std::int16_t samples[8] = {0, 1000, 2000, 1000, 0, -1000, -2000, -1000};
	check(!audio::AudioSystem::playPcm(samples, 8, 8000, 1), "playPcm reports failure", "false");
	check(!audio::AudioSystem::playFile("/definitely/not/here.wav"), "playFile reports failure", "false");
	audio::AudioSystem::stopPlayback();
	audio::AudioSystem::setVolume(50);
	check(audio::AudioSystem::volume() == 50, "setVolume/volume still work", "50");

	std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
	return g_failures == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
	if (argc > 1 && std::strcmp(argv[1], "--no-device") == 0) return runNoDeviceChecks();

	if (!audio::testing::beginOfflineRendering(kSampleRate)) {
		std::printf("could not enter offline rendering mode\n");
		return 2;
	}
	audio::AudioContext context = audio::AudioSystem::sharedContext();
	audio::AudioSystem::setVolume(100);

	const double rate = audio::testing::offlineSampleRate();
	std::printf("engine sample rate: %.0f Hz\n\n", rate);
	if (std::fabs(rate - kSampleRate) > 1.0) {
		std::printf("offline engine did not adopt the requested sample rate\n");
		return 2;
	}

	// ---------------------------------------------------------------- test 1
	// A scheduled square note: silence before, sound during, silence after, and
	// the fundamental the app asked for.
	std::printf("1. scheduled square note, 440 Hz, 0.05s..0.30s\n");
	{
		const double t0 = context.currentTime();
		audio::OscillatorNode oscillator = note(440.0, audio::OscillatorType::Square, t0 + 0.05, t0 + 0.30);
		check(std::fabs(static_cast<double>(oscillator.frequency.value()) - 440.0) < 1e-9,
		      "frequency.value() reads back what was set",
		      format("%.3f Hz", static_cast<double>(oscillator.frequency.value())).c_str());
		check(oscillator.type() == audio::OscillatorType::Square, "type() reads back what was set",
		      oscillator.type() == audio::OscillatorType::Square ? "Square" : "not Square");

		const Capture capture = render(0.40);
		const double before = rms(capture, 0.000, 0.045);
		const double during = rms(capture, 0.070, 0.290);
		const double after = rms(capture, 0.320, 0.400);
		const double frequency = measuredFrequency(capture, 0.070, 0.290);

		check(before < 1e-6, "silence before the scheduled start", format("rms %.9f", before).c_str());
		check(during > 0.05, "non-zero RMS while the note is scheduled", format("rms %.6f", during).c_str());
		check(after < 1e-6, "silence after the scheduled stop", format("rms %.9f", after).c_str());
		check(std::fabs(frequency - 440.0) < 2.0, "measured fundamental matches request",
		      format("%.2f Hz vs 440 Hz", frequency).c_str());
		std::printf("     during=%.6f  before=%.9f  after=%.9f  f=%.2f Hz\n", during, before, after, frequency);
	}

	// ---------------------------------------------------------------- test 2
	// Every waveform sounds, and at the right pitch.
	std::printf("\n2. every OscillatorType sounds at the requested pitch\n");
	{
		struct Case {
			audio::OscillatorType type;
			const char *name;
			double frequency;
		};
		const Case cases[] = {
		    {audio::OscillatorType::Sine, "sine", 330.0},
		    {audio::OscillatorType::Square, "square", 523.0},
		    {audio::OscillatorType::Sawtooth, "sawtooth", 220.0},
		    {audio::OscillatorType::Triangle, "triangle", 659.0},
		};
		for (const Case &item : cases) {
			const double t0 = context.currentTime();
			note(item.frequency, item.type, t0 + 0.02, t0 + 0.22);
			const Capture capture = render(0.30);
			const double level = rms(capture, 0.04, 0.21);
			const double frequency = measuredFrequency(capture, 0.04, 0.21);
			check(level > 0.03 && std::fabs(frequency - item.frequency) < 3.0, item.name,
			      format("rms %.4f, %.2f Hz vs %.0f Hz", level, frequency, item.frequency).c_str());
		}
	}

	// ---------------------------------------------------------------- test 3
	// Concurrent oscillators mix.
	std::printf("\n3. three concurrent oscillators mix\n");
	{
		const double t0 = context.currentTime();
		note(220.0, audio::OscillatorType::Sine, t0 + 0.02, t0 + 0.25);
		note(440.0, audio::OscillatorType::Sine, t0 + 0.02, t0 + 0.25);
		note(660.0, audio::OscillatorType::Sine, t0 + 0.02, t0 + 0.25);
		const Capture capture = render(0.30);
		const double e220 = energyAt(capture, 220.0, 0.05, 0.24);
		const double e440 = energyAt(capture, 440.0, 0.05, 0.24);
		const double e660 = energyAt(capture, 660.0, 0.05, 0.24);
		const double e1500 = energyAt(capture, 1500.0, 0.05, 0.24);
		check(e220 > 0.05 && e440 > 0.05 && e660 > 0.05 && e1500 < 0.01,
		      "all three partials present, nothing at 1500 Hz",
		      format("220:%.4f 440:%.4f 660:%.4f 1500:%.5f", e220, e440, e660, e1500).c_str());
	}

	// ---------------------------------------------------------------- test 4
	// Scheduling: a note scheduled far ahead does not start early.
	std::printf("\n4. start(t) is honoured, not fired immediately\n");
	{
		const double t0 = context.currentTime();
		note(440.0, audio::OscillatorType::Square, t0 + 0.20, t0 + 0.30);
		const Capture capture = render(0.40);
		const double early = rms(capture, 0.00, 0.19);
		const double late = rms(capture, 0.21, 0.29);
		check(early < 1e-6 && late > 0.05, "silent for 200 ms, then sounds",
		      format("first 190ms rms %.9f, then %.6f", early, late).c_str());

		// The onset lands within a render quantum of the requested time.
		std::size_t onset = 0;
		for (std::size_t frame = 0; frame < capture.frames(); ++frame) {
			if (std::fabs(capture.left(frame)) > 0.01) {
				onset = frame;
				break;
			}
		}
		const double onsetSeconds = static_cast<double>(onset) / capture.sampleRate;
		check(std::fabs(onsetSeconds - 0.20) < 0.005, "onset within 5 ms of the scheduled time",
		      format("onset at %.4f s", onsetSeconds).c_str());
	}

	// ---------------------------------------------------------------- test 5
	// currentTime is the engine's running time.
	std::printf("\n5. currentTime() tracks rendered audio\n");
	{
		const double before = context.currentTime();
		render(0.50);
		const double after = context.currentTime();
		check(std::fabs((after - before) - 0.50) < 0.01, "advanced by exactly the rendered duration",
		      format("%.4f s for 0.500 s rendered", after - before).c_str());
	}

	// ---------------------------------------------------------------- test 6
	// Volume really changes the output level.
	std::printf("\n6. setVolume() changes the output level\n");
	{
		audio::AudioSystem::setVolume(100);
		double t0 = context.currentTime();
		note(440.0, audio::OscillatorType::Square, t0 + 0.02, t0 + 0.20);
		const double loud = rms(render(0.25), 0.05, 0.18);

		audio::AudioSystem::setVolume(25);
		t0 = context.currentTime();
		note(440.0, audio::OscillatorType::Square, t0 + 0.02, t0 + 0.20);
		const double quiet = rms(render(0.25), 0.05, 0.18);

		audio::AudioSystem::setVolume(0);
		t0 = context.currentTime();
		note(440.0, audio::OscillatorType::Square, t0 + 0.02, t0 + 0.20);
		const double muted = rms(render(0.25), 0.05, 0.18);

		audio::AudioSystem::setVolume(100);
		check(std::fabs(loud / quiet - 4.0) < 0.2, "volume 100 is 4x volume 25",
		      format("%.6f / %.6f = %.3f", loud, quiet, loud / quiet).c_str());
		check(muted < 1e-9, "volume 0 is silence", format("rms %.9f", muted).c_str());
		check(audio::AudioSystem::volume() == 100, "volume() reads back", format("%d", audio::AudioSystem::volume()).c_str());
	}

	// ---------------------------------------------------------------- test 7
	// No clicks: a sine note's biggest sample-to-sample step stays at the
	// waveform's own slope, at the onset and at the release.
	std::printf("\n7. no click at note start or stop\n");
	{
		const double frequency = 440.0;
		const double t0 = context.currentTime();
		note(frequency, audio::OscillatorType::Sine, t0 + 0.05, t0 + 0.20);
		const Capture capture = render(0.30);
		const double amplitude = peak(capture, 0.06, 0.19);
		const double slope = 2.0 * M_PI * frequency / capture.sampleRate * amplitude;
		const double worst = maxDelta(capture, 0.00, 0.30);
		check(worst < slope * 1.5, "max sample step is the waveform's own slope",
		      format("step %.6f vs slope %.6f", worst, slope).c_str());
	}

	// ---------------------------------------------------------------- test 8
	// A rapid burst of short notes (button-tetris' worst case) all sound.
	std::printf("\n8. rapid short notes (button-tetris burst)\n");
	{
		const double t0 = context.currentTime();
		for (int index = 0; index < 12; ++index) {
			const double start = t0 + 0.02 + 0.03 * index;
			note(280.0 + 40.0 * index, audio::OscillatorType::Square, start, start + 0.024);
		}
		const Capture capture = render(0.45);
		int sounded = 0;
		for (int index = 0; index < 12; ++index) {
			const double start = 0.02 + 0.03 * index;
			if (rms(capture, start + 0.004, start + 0.020) > 0.05) ++sounded;
		}
		check(sounded == 12, "all 12 notes sounded", format("%d/12", sounded).c_str());
		check(maxDelta(capture, 0.0, 0.45) <= 2.0 * peak(capture, 0.0, 0.45) + 1e-6,
		      "no step larger than a full square transition",
		      format("step %.4f, peak %.4f", maxDelta(capture, 0.0, 0.45), peak(capture, 0.0, 0.45)).c_str());
	}

	// ---------------------------------------------------------------- test 9
	// setValueAtTime schedules.
	std::printf("\n9. setValueAtTime() schedules a frequency change\n");
	{
		const double t0 = context.currentTime();
		audio::OscillatorNode oscillator = context.createOscillator();
		oscillator.setType(audio::OscillatorType::Sine);
		oscillator.frequency.setValue(300.0);
		oscillator.frequency.setValueAtTime(900.0, t0 + 0.15);
		oscillator.connect(context.destination());
		oscillator.start(t0 + 0.02);
		oscillator.stop(t0 + 0.28);
		const Capture capture = render(0.35);
		const double first = measuredFrequency(capture, 0.05, 0.14);
		const double second = measuredFrequency(capture, 0.17, 0.27);
		check(std::fabs(first - 300.0) < 4.0 && std::fabs(second - 900.0) < 6.0,
		      "300 Hz before the event, 900 Hz after",
		      format("%.1f Hz then %.1f Hz", first, second).c_str());
	}

	// -------------------------------------------------------------- test 9.5
	// connect() after start()/stop() still produces the note (Web Audio allows
	// the graph to be wired up after the schedule is set).
	std::printf("\n9b. connect() after start()/stop()\n");
	{
		const double t0 = context.currentTime();
		audio::OscillatorNode oscillator = context.createOscillator();
		oscillator.setType(audio::OscillatorType::Square);
		oscillator.frequency.setValue(600.0);
		oscillator.start(t0 + 0.02);
		oscillator.stop(t0 + 0.16);
		oscillator.connect(context.destination());
		const Capture capture = render(0.25);
		const double level = rms(capture, 0.04, 0.15);
		const double after = rms(capture, 0.19, 0.25);
		const double frequency = measuredFrequency(capture, 0.04, 0.15);
		check(level > 0.05 && after < 1e-6 && std::fabs(frequency - 600.0) < 4.0,
		      "late connect still sounds, and still stops",
		      format("rms %.4f then %.9f, %.1f Hz", level, after, frequency).c_str());
	}

	// --------------------------------------------------------------- test 10
	// playPcm.
	std::printf("\n10. AudioSystem::playPcm\n");
	{
		const int sampleRate = 44100;
		const int frames = sampleRate / 4;
		std::vector<std::int16_t> samples(static_cast<std::size_t>(frames));
		for (int frame = 0; frame < frames; ++frame) {
			const double phase = 2.0 * M_PI * 500.0 * static_cast<double>(frame) / sampleRate;
			samples[static_cast<std::size_t>(frame)] = static_cast<std::int16_t>(std::sin(phase) * 20000.0);
		}
		const bool played = audio::AudioSystem::playPcm(samples.data(), samples.size(), sampleRate, 1);
		const Capture capture = render(0.20);
		const double level = rms(capture, 0.02, 0.18);
		const double frequency = measuredFrequency(capture, 0.02, 0.18);
		check(played, "playPcm reported success", played ? "true" : "false");
		check(level > 0.02, "PCM buffer produced output", format("rms %.6f", level).c_str());
		check(std::fabs(frequency - 500.0) < 5.0, "PCM played back at the right rate",
		      format("%.2f Hz vs 500 Hz", frequency).c_str());
		audio::AudioSystem::stopPlayback();
		const double afterStop = rms(render(0.10), 0.02, 0.10);
		check(afterStop < 1e-6, "stopPlayback() silenced it", format("rms %.9f", afterStop).c_str());
	}

	// --------------------------------------------------------------- test 11
	// playFile.
	std::printf("\n11. AudioSystem::playFile\n");
	{
		const std::string path = writeTestWav(700.0, 0.4, 44100);
		if (path.empty()) {
			check(false, "could not write the test wav", "");
		} else {
			const bool played = audio::AudioSystem::playFile(path);
			const Capture capture = render(0.20);
			const double level = rms(capture, 0.02, 0.18);
			const double frequency = measuredFrequency(capture, 0.02, 0.18);
			check(played, "playFile reported success", played ? "true" : "false");
			check(level > 0.02, "file produced output", format("rms %.6f", level).c_str());
			check(std::fabs(frequency - 700.0) < 6.0, "file played at the right pitch",
			      format("%.2f Hz vs 700 Hz", frequency).c_str());
			audio::AudioSystem::stopPlayback();
			check(!audio::AudioSystem::playFile("/definitely/not/here.wav"), "missing file reports failure", "false");
			std::remove(path.c_str());
		}
	}

	// --------------------------------------------------------------- test 12
	// The oscillator pool recycles: an app that creates one oscillator per note
	// forever (button-tetris does) must keep sounding indefinitely.
	std::printf("\n12. 1500 sequential notes (oscillator pool recycles)\n");
	{
		int silent = 0;
		double worstRms = 1.0;
		for (int index = 0; index < 1500; ++index) {
			const double t0 = context.currentTime();
			note(440.0, audio::OscillatorType::Square, t0 + 0.004, t0 + 0.020);
			const Capture capture = render(0.030);
			const double level = rms(capture, 0.008, 0.018);
			if (level < 0.05) ++silent;
			worstRms = std::fmin(worstRms, level);
		}
		check(silent == 0, "every one of 1500 notes sounded",
		      format("%d silent, worst rms %.5f", silent, worstRms).c_str());
	}

	// --------------------------------------------------------------- test 13
	// The app thread mutates oscillator state while the graph renders. Build this
	// with -fsanitize=thread (build-audio-selftest.sh --tsan) to check the
	// lock-free command ring's memory ordering rather than just its behaviour.
	std::printf("\n13. concurrent mutation while rendering\n");
	{
		std::atomic<bool> stop{false};
		std::atomic<int> created{0};
		std::thread mutator([&] {
			audio::AudioContext local = audio::AudioSystem::sharedContext();
			while (!stop.load()) {
				const double now = local.currentTime();
				audio::OscillatorNode oscillator = local.createOscillator();
				oscillator.setType(audio::OscillatorType::Sine);
				oscillator.frequency.setValue(300.0 + (created.load() % 400));
				oscillator.connect(local.destination());
				oscillator.start(now + 0.005);
				oscillator.frequency.setValue(500.0);
				oscillator.stop(now + 0.030);
				(void)oscillator.frequency.value();
				(void)oscillator.type();
				created.fetch_add(1);
			}
		});
		double loudest = 0.0;
		for (int block = 0; block < 40; ++block) loudest = std::fmax(loudest, rms(render(0.02), 0.0, 0.02));
		stop.store(true);
		mutator.join();
		check(created.load() > 0 && loudest > 0.0, "no crash, and audio kept flowing",
		      format("%d oscillators, loudest block rms %.5f", created.load(), loudest).c_str());
	}

	audio::testing::endOfflineRendering();

	std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
	return g_failures == 0 ? 0 : 1;
}

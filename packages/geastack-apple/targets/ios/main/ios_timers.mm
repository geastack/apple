#import <Foundation/Foundation.h>

#include "services/frame_scheduler.h"

#include <cstdint>
#include <mach/mach_time.h>

namespace {

int millis_since_boot()
{
	static mach_timebase_info_data_t tb = {0, 0};
	if (tb.denom == 0) mach_timebase_info(&tb);
	const std::uint64_t ns = mach_absolute_time() * tb.numer / tb.denom;
	return static_cast<int>(ns / 1000000ULL);
}

int g_frame_interval_ms = gea::framework::services::FrameScheduler::kDefaultFrameIntervalMs;

}  // namespace

extern "C" int gea_embedded_now_ms(void)
{
	return millis_since_boot();
}

namespace gea::framework::services {

EventQueue FrameScheduler::createEventQueue() { return EventQueue{}; }
EventQueue FrameScheduler::eventQueue() { return EventQueue{}; }
bool FrameScheduler::sendEvent(const gea::framework::events::Event &, int) { return true; }
bool FrameScheduler::receiveEvent(gea::framework::events::Event *) { return false; }
void FrameScheduler::start(EventQueue) {}
void FrameScheduler::runFrame(const FrameCallbacks &callbacks)
{
	if (callbacks.frame) callbacks.frame(millis_since_boot(), callbacks.context);
}
void FrameScheduler::setFrameIntervalMs(int intervalMs)
{
	if (intervalMs < kMinFrameIntervalMs) intervalMs = kMinFrameIntervalMs;
	if (intervalMs > kMaxFrameIntervalMs) intervalMs = kMaxFrameIntervalMs;
	g_frame_interval_ms = intervalMs;
}
int FrameScheduler::frameIntervalMs() { return g_frame_interval_ms; }
void FrameScheduler::setFrameRate(double fps)
{
	if (fps <= 0.0) return;
	setFrameIntervalMs(static_cast<int>(1000.0 / fps + 0.5));
}
double FrameScheduler::frameRate() { return 1000.0 / static_cast<double>(g_frame_interval_ms); }
int FrameScheduler::nowMs() { return millis_since_boot(); }

}  // namespace gea::framework::services

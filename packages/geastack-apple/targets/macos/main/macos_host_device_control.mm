// gea::host::DeviceControl::exec — host shell exec for gea (CSS-runtime) apps on
// macOS. The gea Companion drives scripts/esp32-device-control.py (GEADEV over
// USB) and scripts/install-app.mjs (install/uninstall) through this.
//
// NON-BLOCKING by design: the macOS gea runtime runs its rAF/update loop on the
// MAIN thread. A synchronous NSTask here (≈5s per call when the watch is offline,
// and the companion polls two per cycle) would freeze the window — no clicks, no
// scrolling, no resize. So exec() returns the LAST cached result for a command
// immediately and refreshes it on a background queue; the reactive store reads the
// updated value on a later tick. Action commands (setFace/brightness/install) are
// fire-and-forget — the ignored return is fine, the work still runs off-main.
#import <Foundation/Foundation.h>

#include <map>
#include <mutex>
#include <set>
#include <string>

#include "host/device_control.h"

namespace {
std::mutex g_mutex;
std::map<std::string, std::string> g_cache;
std::set<std::string> g_inflight;

std::string trimTrailingNewlines(std::string value)
{
	while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) {
		value.pop_back();
	}
	return value;
}

std::string runBlocking(const std::string &command)
{
	@autoreleasepool {
		NSString *cmd = [NSString stringWithUTF8String:command.c_str()];
		NSTask *task = [[NSTask alloc] init];
		// -lc: login shell so PATH includes the user's python3/node (pyserial etc.).
		task.launchPath = @"/bin/bash";
		task.arguments = @[ @"-lc", cmd ];
		NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
		NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
		if (resourcePath) {
			environment[@"GEA_COMPANION_RESOURCES"] = resourcePath;
			NSString *toolsPath = [resourcePath stringByAppendingPathComponent:@"CompanionTools"];
			environment[@"GEA_COMPANION_TOOLS"] = toolsPath;
		}
		task.environment = environment;
		NSPipe *pipe = [NSPipe pipe];
		task.standardOutput = pipe;
		task.standardError = pipe;

		std::string result;
		@try {
			[task launch];
			NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
			[task waitUntilExit];
			NSString *out = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			result = out ? std::string([out UTF8String]) : std::string();
		} @catch (NSException *ex) {
			result = std::string();
		}
		return trimTrailingNewlines(result);
	}
}
}  // namespace

std::string gea::host::DeviceControlFacade::exec(const std::string &command) const
{
	std::string cached;
	bool shouldDispatch = false;
	{
		std::lock_guard<std::mutex> lock(g_mutex);
		auto it = g_cache.find(command);
		if (it != g_cache.end()) cached = it->second;
		// De-dupe only concurrent identical runs; once a run finishes, the next
		// exec() of the same command re-dispatches — so polls refresh each cycle
		// and repeated actions re-fire.
		if (g_inflight.find(command) == g_inflight.end()) {
			g_inflight.insert(command);
			shouldDispatch = true;
		}
	}
	if (shouldDispatch) {
		std::string cmd = command;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			std::string result = runBlocking(cmd);
			std::lock_guard<std::mutex> lock(g_mutex);
			g_cache[cmd] = result;
			g_inflight.erase(cmd);
		});
	}
	return cached;
}

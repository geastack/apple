// Native implementation of @geajs/apple/AppKit runDeviceCommand(command).
//
// A small escape hatch for companion apps that drive external tooling: runs a
// shell command via /bin/bash and returns its combined stdout+stderr as a
// string. The gea Companion uses it to talk to the watch over USB through
// scripts/esp32-device-control.py (GEADEV protocol). The apple-native bridge
// is C++/ObjC++, so we have full NSTask/Foundation access here even though the
// TS layer only sees a `string -> string` function.
//
// Same wiring pattern as installRootViewController/installToolbar in
// macos_main.mm: a thunk declared by the generated bridge header, implemented
// natively, compiled + linked by build-macos.sh.

#import <Foundation/Foundation.h>

#include <cstdio>
#include <string>

#if __has_include("gea/apple/native_bridge.h")
#include "gea/apple/native_bridge.h"

std::string gea::apple::AppKit::runDeviceCommand(std::string command)
{
	@autoreleasepool {
		NSString *cmd = [NSString stringWithUTF8String:command.c_str()];
		NSTask *task = [[NSTask alloc] init];
		// -lc: login shell so PATH includes the user's python3 (with pyserial).
		task.launchPath = @"/bin/bash";
		task.arguments = @[ @"-lc", cmd ];
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
			result = std::string("EXC: ") + (ex.reason ? [ex.reason UTF8String] : "exception");
		}

		// Append to a log so headless runs (locked Mac, no visible window) can
		// still confirm the command ran and what the device returned.
		FILE *f = std::fopen("/tmp/gea-companion-device.log", "a");
		if (f) {
			std::fprintf(f, "$ %s\n%s\n---\n", command.c_str(), result.c_str());
			std::fclose(f);
		}
		return result;
	}
}

#endif  // __has_include("gea/apple/native_bridge.h")

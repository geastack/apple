#import <AppKit/AppKit.h>
#include "macos_background_test.h"
#include <cstdio>

int main() {
    @autoreleasepool {
        // Validate a malformed mode before even creating NSApplication.
        if (!gea::macos::background_test::enabled()) return 79;
        const pid_t foregroundBefore = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        NSApplication* app = NSApplication.sharedApplication;
        gea::macos::background_test::configure(app);
        NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        window.releasedWhenClosed = NO;
        [window setContentView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)]];
        gea::macos::background_test::present(window);
        gea::macos::background_test::checkApplication(app);
        const pid_t foregroundAfter = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        std::printf("{\"policy\":%ld,\"active\":%s,\"visible\":%s,\"key\":%s,\"main\":%s,\"foregroundBefore\":%d,\"foregroundAfter\":%d}\n",
            static_cast<long>(app.activationPolicy), app.active ? "true" : "false",
            window.visible ? "true" : "false", window.keyWindow ? "true" : "false",
            window.mainWindow ? "true" : "false", foregroundBefore, foregroundAfter);
        [window close];
        return 0;
    }
}

#pragma once

#import <AppKit/AppKit.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// Hidden-window test mode. Ordinary user launches keep normal AppKit
// presentation. Tests can instantiate the real application without ordering a
// window, becoming active, or opening Gea audio. This is not a WebView path.
namespace gea::macos::background_test {
[[noreturn]] inline void refuse(const char* reason) {
    std::fprintf(stderr, "Gea background UI test refused: %s\n", reason);
    std::fflush(stderr);
    std::_Exit(78);
}
inline bool enabled() {
    static const bool value = [] {
        const char* flag = std::getenv("GEA_MACOS_BACKGROUND_TEST");
        if (!flag) return false;
        if (std::strcmp(flag, "1") != 0)
            refuse("GEA_MACOS_BACKGROUND_TEST must be absent or exactly 1");
        return true;
    }();
    return value;
}
inline void checkApplication(NSApplication* app) {
    if (!enabled()) return;
    if (!app || app.activationPolicy != NSApplicationActivationPolicyProhibited || app.active)
        refuse("application must stay prohibited and inactive");
    for (NSWindow* window in app.windows) {
        if (window.visible || window.keyWindow || window.mainWindow)
            refuse("all owned windows must stay hidden, nonkey and nonmain");
    }
}
inline void configure(NSApplication* app) {
    if (!enabled()) return;
    const char* audio = std::getenv("GEA_AUDIO_DISABLED");
    if (!audio || std::strcmp(audio, "1") != 0)
        refuse("GEA_AUDIO_DISABLED=1 is required before application startup");
    [app setActivationPolicy:NSApplicationActivationPolicyProhibited];
    checkApplication(app);
}
inline void present(NSWindow* window) {
    if (enabled()) {
        checkApplication(NSApp);
        if (!window || window.visible || window.keyWindow || window.mainWindow)
            refuse("window presentation is forbidden");
        return;
    }
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
} // namespace gea::macos::background_test

#import <AppKit/AppKit.h>

#include "apps.h"

#include <string>

// macOS app-launcher platform. When the JSX-level `Apps.launch('foo')` runs,
// AppManager::launch routes through this platform. We don't have in-process
// app swapping yet (that'd need every app's __gea_top_level bundled into one
// binary with a registry — like ESP32's resident-app system), so we cheat:
// find dist/<id>/*.app next to the currently running bundle, open it with
// NSWorkspace, and terminate self. Result is "click a tile → next app's
// window appears, launcher window goes away" — same UX as the watch, just
// realized via separate Mac processes.
//
// If the target .app hasn't been built yet, we log a message and stay in
// the launcher. The user runs `targets/macos/build-macos.sh <id>` first.

namespace {

class MacosAppLauncherPlatform final : public gea::framework::apps::AppLauncherPlatform {
public:
	explicit MacosAppLauncherPlatform(std::string currentId) : currentId_(std::move(currentId)) {}

	const char *currentInstalledAppId() override { return currentId_.c_str(); }
	bool runningAppIsLauncher(const char *launcherAppId) override
	{
		if (!launcherAppId) return false;
		return currentId_ == launcherAppId;
	}

	bool launchInstalledApp(const char *appId) override
	{
		if (!appId || !appId[0]) return false;
		NSString *target = [NSString stringWithUTF8String:appId];
		NSString *bundle = findBundleForAppId(target);
		if (!bundle) {
			NSLog(@"[gea-launch] no built .app for '%@' under dist/. Run "
			      @"targets/macos/build-macos.sh %@ first.",
			      target, target);
			return false;
		}
		NSURL *url = [NSURL fileURLWithPath:bundle];
		NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
		cfg.activates = YES;
		cfg.createsNewApplicationInstance = YES;  // don't reuse a running instance of the same app
		[[NSWorkspace sharedWorkspace] openApplicationAtURL:url
		                                      configuration:cfg
		                                  completionHandler:^(NSRunningApplication *app, NSError *err) {
			(void)app;
			if (err) NSLog(@"[gea-launch] open failed: %@", err);
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSApp terminate:nil];
			});
		}];
		return true;
	}

private:
	std::string currentId_;

	static NSString *findBundleForAppId(NSString *appId)
	{
		// Default bundle: .../dist/<currentId>/<Name>.app. Tagged builds use
		// .../dist/.namespaces/<tag>/<currentId>/<Name>.app. In both layouts,
		// two parent traversals land on the root whose children are app ids, so a
		// tagged launcher opens apps built in the same output namespace.
		NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
		NSString *distDir = [[bundlePath stringByDeletingLastPathComponent]
		    stringByDeletingLastPathComponent];
		NSString *appDir = [distDir stringByAppendingPathComponent:appId];
		NSError *err = nil;
		NSArray<NSString *> *entries =
		    [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appDir error:&err];
		if (!entries) return nil;
		for (NSString *name in entries) {
			if ([name hasSuffix:@".app"]) return [appDir stringByAppendingPathComponent:name];
		}
		return nil;
	}
};

}  // namespace

namespace gea::macos {

void installAppLauncherPlatform(const char *currentAppId)
{
	static MacosAppLauncherPlatform *instance = nullptr;
	if (instance) return;
	instance = new MacosAppLauncherPlatform(currentAppId ? currentAppId : "");
	gea::framework::apps::AppManager::setPlatform(instance);
}

}  // namespace gea::macos

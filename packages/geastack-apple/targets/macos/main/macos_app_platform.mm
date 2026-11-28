#import <AppKit/AppKit.h>

#include "geaos.h"

#include <string>
#include <vector>

// The macOS GeaOS host. Apps on macOS are bundled with the shell: the ones
// built next to this one (dist/<id>/<Name>.app) are its bundledApps(), and
// launching one opens that bundle and quits this process -- "click a tile,
// the app's window appears, Home's goes away", like the watch, realized as
// separate Mac processes. Apps are never downloaded and loaded at run time
// on Apple targets.
//
// An app that has not been built yet is not listed; build it with
// `gea build --target macos <id>`.

namespace {

// The bundle that plays Home.
constexpr const char *kHomeAppId = "app-launcher";

class MacosAppHost final : public gea::geaos::AppHost {
public:
	explicit MacosAppHost(std::string currentId) : currentId_(std::move(currentId)) {}

	const char *targetKey() const override { return "macos"; }
	// Bundled apps are built with this shell; there is nothing to mismatch.
	const char *abi() const override { return "macos-bundled"; }
	const char *firmwareId() const override { return currentId_.c_str(); }
	const char *runningAppId() const override { return currentId_ == kHomeAppId ? "" : currentId_.c_str(); }

	std::vector<gea::geaos::InstalledApp> bundledApps() const override
	{
		std::vector<gea::geaos::InstalledApp> apps;
		NSString *dist = distDirectory();
		NSArray<NSString *> *ids = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dist error:nil];
		for (NSString *candidate in ids) {
			const char *id = candidate.UTF8String;
			if (!gea::geaos::isValidAppId(id) || std::string(id) == kHomeAppId) continue;
			NSString *bundle = findBundleForAppId(candidate);
			if (!bundle) continue;
			gea::geaos::InstalledApp app;
			app.manifest.id = id;
			NSString *name = [[bundle lastPathComponent] stringByDeletingPathExtension];
			app.manifest.name = name.length ? name.UTF8String : id;
			app.manifest.abi = abi();
			app.volumeId = "bundle";
			app.location = bundle.UTF8String;
			apps.push_back(std::move(app));
		}
		return apps;
	}

	bool launch(const gea::geaos::InstalledApp &app, std::string &error) override
	{
		return open(app.manifest.id.c_str(), error);
	}

	bool home(std::string &error) override
	{
		if (currentId_ == kHomeAppId) {
			error = "Home is already running";
			return false;
		}
		return open(kHomeAppId, error);
	}

private:
	bool open(const char *appId, std::string &error)
	{
		NSString *target = [NSString stringWithUTF8String:appId];
		NSString *bundle = findBundleForAppId(target);
		if (!bundle) {
			NSLog(@"[gea-launch] no built .app for '%@' under dist/. Run gea build --target macos %@ first.", target, target);
			error = std::string("no built app for ") + appId;
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
			if (err) {
				NSLog(@"[gea-launch] open failed: %@", err);
				gea::geaos::Launcher::setLastError(err.localizedDescription.UTF8String);
				return;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSApp terminate:nil];
			});
		}];
		return true;
	}

	// Default bundle: .../dist/<currentId>/<Name>.app. Tagged builds use
	// .../dist/.namespaces/<tag>/<currentId>/<Name>.app. In both layouts two
	// parent traversals land on the folder whose children are app ids, so a
	// tagged Home opens apps built in the same output namespace.
	static NSString *distDirectory()
	{
		NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
		return [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	}

private:
	std::string currentId_;

	static NSString *findBundleForAppId(NSString *appId)
	{
		NSString *appDir = [distDirectory() stringByAppendingPathComponent:appId];
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
	static MacosAppHost *instance = nullptr;
	if (instance) return;
	instance = new MacosAppHost(currentAppId ? currentAppId : "");
	gea::geaos::Launcher::setHost(instance);
}

}  // namespace gea::macos

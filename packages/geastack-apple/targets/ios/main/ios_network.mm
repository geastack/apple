/* targets/ios/main/ios_network.mm
 * Real HTTP(S) for the framework's fetch facade, via NSURLSession.
 *
 * core's host/host/fetch.cpp has three arms: browser (emscripten), ESP-IDF, and
 * a desktop fallback that calls two WEAK hooks —
 *   test_record_request(url, init)   then   test_canned_response(url)
 * — and returns whatever the latter produces (empty by default). Android, macOS
 * and Raspberry Pi OS strong-override that seam to inject real responses; until
 * this file existed iOS did not, so every fetch on iOS resolved to an empty
 * canned response. This is the macOS backend (targets/macos/main/macos_network.mm)
 * with one substitution: the WiFi status driver reads NWPathMonitor instead of
 * SystemConfiguration's dynamic store, which is macOS-only.
 *
 * The fetch seam is synchronous, so each request parks its calling thread on a
 * semaphore until the session's completion handler fires — the callers are
 * detached fetchAsync threads or the frame thread for a synchronous app fetch,
 * and the session's delegate queue is its own, so the wait cannot deadlock.
 * test_canned_response only receives the URL, so test_record_request stashes the
 * request init in a thread_local for it to pick up (both hooks run back-to-back
 * on the same thread).
 */

#import <Foundation/Foundation.h>
#import <Network/Network.h>

#include "host/fetch.h"
#include "wifi.h"

#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

namespace {

thread_local gea::host::FetchRequestInit t_pending_init;
thread_local bool t_has_pending_init = false;

// One shared session for every caller: NSURLSession is thread-safe and pools
// keep-alive connections per host across threads, so sequential requests pay the
// TCP + TLS handshake once while worker threads still fetch in parallel.
NSURLSession *sharedSession()
{
	static NSURLSession *session;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
		config.HTTPAdditionalHeaders = @{ @"User-Agent": @"gea-ios/1.0" };
		config.timeoutIntervalForRequest = 30.0;
		session = [NSURLSession sessionWithConfiguration:config];
	});
	return session;
}

gea::host::FetchResponse sessionFetch(const std::string &url, const gea::host::FetchRequestInit &init)
{
	gea::host::FetchResponse response;
	NSURL *requestUrl = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()] ?: @""];
	if (!requestUrl) {
		std::fprintf(stderr, "[ios net] fetch rejected malformed url %s\n", url.c_str());
		return response;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
	const std::string method = init.method.empty() ? "GET" : init.method;
	request.HTTPMethod = [NSString stringWithUTF8String:method.c_str()] ?: @"GET";
	if (init.timeout_ms > 0) request.timeoutInterval = init.timeout_ms / 1000.0;
	for (const auto &kv : init.headers) {
		NSString *name = [NSString stringWithUTF8String:kv.first.c_str()];
		NSString *value = [NSString stringWithUTF8String:kv.second.c_str()];
		if (name && value) [request setValue:value forHTTPHeaderField:name];
	}
	if (!init.body.empty() && method != "GET" && method != "HEAD") {
		request.HTTPBody = [NSData dataWithBytes:init.body.data() length:init.body.size()];
	}

	// Park this thread until the completion handler fires on the session's own
	// delegate queue. Redirects are followed and gzip/deflate bodies decoded by
	// the session before the handler runs.
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	__block NSData *body = nil;
	__block NSHTTPURLResponse *httpResponse = nil;
	__block NSError *error = nil;
	NSURLSessionDataTask *task = [sharedSession()
	    dataTaskWithRequest:request
	      completionHandler:^(NSData *taskData, NSURLResponse *taskResponse, NSError *taskError) {
		      body = taskData;
		      if ([taskResponse isKindOfClass:[NSHTTPURLResponse class]]) {
			      httpResponse = (NSHTTPURLResponse *)taskResponse;
		      }
		      error = taskError;
		      dispatch_semaphore_signal(done);
	      }];
	[task resume];
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

	if (error) {
		std::fprintf(stderr, "[ios net] fetch %s failed: %s\n", url.c_str(),
		             error.localizedDescription.UTF8String ?: "unknown error");
		return response;
	}
	if (httpResponse) {
		const NSInteger code = httpResponse.statusCode;
		response.status = static_cast<double>(code);
		response.ok = code >= 200 && code < 300;
		response.status_text = std::string([NSHTTPURLResponse localizedStringForStatusCode:code].UTF8String ?: "");
		NSDictionary *headerFields = httpResponse.allHeaderFields;
		for (id name in headerFields) {
			id value = headerFields[name];
			if ([name isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
				response.headers[std::string([(NSString *)name UTF8String] ?: "")] =
				    std::string([(NSString *)value UTF8String] ?: "");
			}
		}
	}
	if (body.length > 0) {
		const auto *bytes = static_cast<const std::uint8_t *>(body.bytes);
		response.body.assign(bytes, bytes + body.length);
	}
	return response;
}

}  // namespace

namespace gea::framework::host {

// Strong overrides of the weak desktop-fallback hooks in host/host/fetch.cpp.
void test_record_request(const std::string &, const gea::host::FetchRequestInit &init)
{
	t_pending_init = init;
	t_has_pending_init = true;
}

gea::host::FetchResponse test_canned_response(const std::string &url)
{
	gea::host::FetchRequestInit init;
	if (t_has_pending_init) {
		init = std::move(t_pending_init);
		t_pending_init = {};
		t_has_pending_init = false;
	}
	return sessionFetch(url, init);
}

}  // namespace gea::framework::host

namespace {

// WiFi *status* driver. Several apps gate remote fetches on wifi().connected()
// (weather sits on placeholders without it), so the phone has to report its real
// reachability even though fetch itself just uses the host TCP stack. NWPathMonitor
// publishes that asynchronously: it delivers the first path update shortly after
// start, so the flag begins optimistic — same choice the Android driver makes when
// its bridge has not answered yet — rather than making apps wait out a false
// "offline" on the first frames. Cellular counts as satisfied, which is the honest
// answer to "can I reach the network". Scanning and credential configuration are
// no-ops: iOS owns the link and gives apps no way to join a network.
class IosWifiDriver final : public gea::framework::network::WifiDriver {
public:
	bool init() override
	{
		if (monitor_) return true;
		monitor_ = nw_path_monitor_create();
		if (!monitor_) return false;
		queue_ = dispatch_queue_create("gea.ios.network.path", DISPATCH_QUEUE_SERIAL);
		nw_path_monitor_set_queue(monitor_, queue_);
		std::atomic<bool> *flag = &connected_;
		nw_path_monitor_set_update_handler(monitor_, ^(nw_path_t path) {
			const nw_path_status_t status = nw_path_get_status(path);
			flag->store(status == nw_path_status_satisfied || status == nw_path_status_satisfiable,
			            std::memory_order_relaxed);
		});
		nw_path_monitor_start(monitor_);
		return true;
	}

	bool enabled() const override { return enabled_; }
	void setEnabled(bool enabled) override { enabled_ = enabled; }
	bool connected() const override { return enabled_ && connected_.load(std::memory_order_relaxed); }
	int rssi() override { return connected() ? -50 : 0; }
	std::string ssid() override { return connected() ? "ios" : ""; }
	std::string ip() const override { return ""; }
	std::string mac() override { return ""; }
	void configure(const std::string &, const std::string &) override {}
	void scan() override {}
	bool scanning() const override { return false; }
	int scanCount() const override { return 0; }
	gea::framework::network::WifiNetwork networkAt(int) const override { return {}; }
	std::vector<gea::framework::network::WifiNetwork> scanResults() const override { return {}; }

private:
	nw_path_monitor_t monitor_ = nullptr;
	dispatch_queue_t queue_ = nullptr;
	std::atomic<bool> connected_{true};
	bool enabled_ = true;
};

}  // namespace

namespace gea::ios {

void installWifiDriver()
{
	static IosWifiDriver driver;
	driver.init();
	gea::framework::network::WifiAdapter::setDriver(&driver);
}

}  // namespace gea::ios

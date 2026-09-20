/* targets/macos/main/macos_network.mm
 * Real HTTP(S) for the framework's fetch facade, via NSURLSession.
 *
 * core's host/host/fetch.cpp has three arms: browser (emscripten), ESP-IDF,
 * and a desktop fallback that calls two WEAK hooks —
 *   test_record_request(url, init)   then   test_canned_response(url)
 * — and returns whatever the latter produces (empty by default). The Android
 * and Raspberry Pi OS targets strong-override that seam to inject real
 * responses; this file does the same with NSURLSession, the canonical macOS
 * networking stack (system proxy/PAC settings, HTTP/2, TLS session reuse,
 * and connection keep-alive all come from the shared session's pool).
 *
 * The fetch seam is synchronous, so each request parks its calling thread on
 * a semaphore until the session's completion handler fires — the callers are
 * tile-loader workers, detached fetchAsync threads, or the frame thread for
 * a synchronous app fetch, and the session's delegate queue is its own, so
 * the wait cannot deadlock. test_canned_response only receives the URL, so
 * test_record_request stashes the request init in a thread_local for it to
 * pick up (both hooks run back-to-back on the same thread).
 */

#import <Foundation/Foundation.h>

#include "host/fetch.h"
#include "wifi.h"

#include <cstdio>
#include <mutex>
#include <string>
#include <vector>

#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if_dl.h>
#include <netinet/in.h>

namespace {

thread_local gea::host::FetchRequestInit t_pending_init;
thread_local bool t_has_pending_init = false;

// One shared session for every caller: NSURLSession is thread-safe and pools
// keep-alive connections per host across threads, so sequential tile fetches
// pay the TCP + TLS handshake once (same effect the ESP backend gets from its
// per-task esp_http_client) while worker threads still fetch in parallel.
NSURLSession *sharedSession()
{
	static NSURLSession *session;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
		config.HTTPAdditionalHeaders = @{ @"User-Agent": @"gea-macos/1.0" };
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
		std::fprintf(stderr, "[macos net] fetch rejected malformed url %s\n", url.c_str());
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
		std::fprintf(stderr, "[macos net] fetch %s failed: %s\n", url.c_str(),
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

// WiFi *status* driver. Several apps gate remote fetches on
// `wifi().connected()` (e.g. maps skips tile downloads without it), so the
// desktop must report its real link state even though fetch itself just uses
// the host TCP stack. "Connected" = configd has a primary (default-route)
// IPv4 interface — true for wired Ethernet too, which is the honest answer
// to "can I reach the network". Scanning/configuration are desktop no-ops
// (the system owns the link).
class MacWifiDriver final : public gea::framework::network::WifiDriver {
public:
	bool init() override { return true; }
	bool enabled() const override { return true; }
	void setEnabled(bool) override {}
	bool connected() const override { return !primaryInterface().empty(); }
	int rssi() override { return connected() ? -50 : 0; }
	std::string ssid() override { return primaryInterface(); }
	std::string ip() const override
	{
		const std::string iface = primaryInterface();
		if (iface.empty()) return "";
		std::string result;
		struct ifaddrs *addrs = nullptr;
		if (getifaddrs(&addrs) != 0) return "";
		for (struct ifaddrs *a = addrs; a; a = a->ifa_next) {
			if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
			if (iface != a->ifa_name) continue;
			char buf[INET_ADDRSTRLEN] = {0};
			const auto *sin = reinterpret_cast<const struct sockaddr_in *>(a->ifa_addr);
			if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) result = buf;
			break;
		}
		freeifaddrs(addrs);
		return result;
	}
	std::string mac() override
	{
		const std::string iface = primaryInterface();
		if (iface.empty()) return "";
		std::string result;
		struct ifaddrs *addrs = nullptr;
		if (getifaddrs(&addrs) != 0) return "";
		for (struct ifaddrs *a = addrs; a; a = a->ifa_next) {
			if (!a->ifa_addr || a->ifa_addr->sa_family != AF_LINK) continue;
			if (iface != a->ifa_name) continue;
			const auto *sdl = reinterpret_cast<const struct sockaddr_dl *>(a->ifa_addr);
			if (sdl->sdl_alen == 6) {
				const auto *ll = reinterpret_cast<const unsigned char *>(LLADDR(sdl));
				char buf[18];
				std::snprintf(buf, sizeof(buf), "%02x:%02x:%02x:%02x:%02x:%02x",
				              ll[0], ll[1], ll[2], ll[3], ll[4], ll[5]);
				result = buf;
			}
			break;
		}
		freeifaddrs(addrs);
		return result;
	}
	void configure(const std::string &, const std::string &) override {}
	void scan() override {}
	bool scanning() const override { return false; }
	int scanCount() const override { return 0; }
	gea::framework::network::WifiNetwork networkAt(int) const override { return {}; }
	std::vector<gea::framework::network::WifiNetwork> scanResults() const override { return {}; }

private:
	// Interface of the system default route: configd publishes it as
	// State:/Network/Global/IPv4 → PrimaryInterface (absent while offline).
	static std::string primaryInterface()
	{
		SCDynamicStoreRef store = SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("gea-macos-network"), nullptr, nullptr);
		if (!store) return "";
		std::string result;
		CFPropertyListRef value = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
		if (value) {
			if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
				const void *iface = CFDictionaryGetValue((CFDictionaryRef)value, CFSTR("PrimaryInterface"));
				if (iface && CFGetTypeID((CFTypeRef)iface) == CFStringGetTypeID()) {
					char buf[64] = {0};
					if (CFStringGetCString((CFStringRef)iface, buf, sizeof(buf), kCFStringEncodingUTF8)) result = buf;
				}
			}
			CFRelease(value);
		}
		CFRelease(store);
		return result;
	}
};

}  // namespace

namespace gea::macos {

void installWifiDriver()
{
	static MacWifiDriver driver;
	gea::framework::network::WifiAdapter::setDriver(&driver);
}

}  // namespace gea::macos

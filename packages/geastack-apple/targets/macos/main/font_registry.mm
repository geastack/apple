#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>

#include "font_registry.h"
#include "graphics/font.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace gea::macos {

namespace {

// Family name registry. Indexed by familyId; ids are handed out in the order
// the framework first asks for them. CSS family lookups all flow through
// generated::lookupFontFamily below.
//
// Construct-on-first-use, NOT namespace-scope globals: an app with a static
// `font-family` CSS rule (maps' device-fonts.css) registers it from a GLOBAL
// CONSTRUCTOR — the generated GeaPluginCppPreludeRegistration calls
// registerStaticFontFamilyRule → lookupFontFamily during dyld initializers,
// which may run BEFORE this translation unit's own initializers. With plain
// globals the unordered_map was still zeroed BSS at that point (max load
// factor 0 → __next_prime overflow_error → abort at launch), and locking the
// unconstructed mutex is UB. A function-local static is constructed on first
// use (thread-safe since C++11), so the registry is valid whenever reached.
struct FamilyRegistry {
	std::mutex lock;
	std::vector<std::string> names;
	std::unordered_map<std::string, int> byName;
};

FamilyRegistry &familyRegistry()
{
	static FamilyRegistry registry;
	return registry;
}

int registerFamily(const std::string &name)
{
	FamilyRegistry &registry = familyRegistry();
	std::scoped_lock guard(registry.lock);
	auto it = registry.byName.find(name);
	if (it != registry.byName.end()) return it->second;
	const int id = static_cast<int>(registry.names.size());
	registry.names.push_back(name);
	registry.byName.emplace(name, id);
	return id;
}

NSString *familyForId(int id)
{
	FamilyRegistry &registry = familyRegistry();
	std::scoped_lock guard(registry.lock);
	if (id < 0 || static_cast<size_t>(id) >= registry.names.size()) return nil;
	return [NSString stringWithUTF8String:registry.names[id].c_str()];
}

// Raw TTF/OTF bytes of the bundle's custom fonts, keyed by lowercased family
// name. The engine's runtime TTF rasterizer (GEA_EMBEDDED_TTF_RUNTIME_FONTS)
// bakes canvas glyph atlases from these via lookupRuntimeTtfFontForFamily —
// without it, ctx.fillText fell back to the builtin bitmap font and canvas
// labels (maps' place pins) rendered garbled. The byte buffers must live for
// the process lifetime: the rasterizer keeps stbtt_fontinfo pointers into
// them across atlas rebuilds. Construct-on-first-use for the same dyld-
// initializer-ordering reason as FamilyRegistry above.
struct TtfByteRegistry {
	std::mutex lock;
	std::unordered_map<std::string, std::vector<std::uint8_t>> byFamily;
};

TtfByteRegistry &ttfByteRegistry()
{
	static TtfByteRegistry registry;
	return registry;
}

std::string lowercased(const std::string &value)
{
	std::string out = value;
	std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return out;
}

void registerTtfBytesForFamily(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data.length == 0) return;
	CTFontDescriptorRef desc = CTFontManagerCreateFontDescriptorFromData((__bridge CFDataRef)data);
	if (!desc) return;
	CFStringRef family = (CFStringRef)CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute);
	CFRelease(desc);
	if (!family) return;
	char buf[256] = {0};
	const bool ok = CFStringGetCString(family, buf, sizeof(buf), kCFStringEncodingUTF8);
	CFRelease(family);
	if (!ok || !buf[0]) return;
	const auto *bytes = static_cast<const std::uint8_t *>(data.bytes);
	TtfByteRegistry &registry = ttfByteRegistry();
	std::scoped_lock guard(registry.lock);
	// First face wins (e.g. Inter-Regular before other weights of the family):
	// the runtime rasterizer keys on the family alone.
	registry.byFamily.emplace(lowercased(buf), std::vector<std::uint8_t>(bytes, bytes + data.length));
}

}  // namespace

// Non-anonymous accessor for the generated-hook namespace below: resolve a
// framework familyId to the bundled TTF bytes feeding the runtime rasterizer.
const std::uint8_t *runtimeTtfBytesForFamilyId(int familyId, unsigned long *length)
{
	if (length) *length = 0;
	NSString *family = familyForId(familyId);
	if (!family || family.length == 0) return nullptr;
	TtfByteRegistry &registry = ttfByteRegistry();
	std::scoped_lock guard(registry.lock);
	const auto it = registry.byFamily.find(lowercased(family.UTF8String));
	if (it == registry.byFamily.end()) return nullptr;
	if (length) *length = it->second.size();
	return it->second.data();
}

static NSFont *self_resolveFont(int fontId, CGFloat size);

NSFont *fontForId(int fontId, int sizePx)
{
	CGFloat size = sizePx > 0 ? static_cast<CGFloat>(sizePx) : [NSFont systemFontSize];

	// Cache resolved fonts by (fontId, size). `+[NSFont fontWithName:size:]` and
	// the CTFontDescriptor fallback below both do a CoreText font-descriptor
	// match, which is expensive — and this is called for EVERY text node on
	// EVERY frame (renderer sync + layout measurement). Without this cache,
	// CoreText font matching dominated the profile and pegged a CPU core. The
	// set of (family, size) pairs an app uses is tiny, so the cache stays small.
	static NSMutableDictionary<NSNumber *, NSFont *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
	NSNumber *key = @(static_cast<long long>(fontId) * 100000LL + llround(size));
	@synchronized(cache) {
		NSFont *hit = cache[key];
		if (hit) return hit;
	}
	NSFont *resolved = self_resolveFont(fontId, size);
	if (resolved) {
		@synchronized(cache) { cache[key] = resolved; }
	}
	return resolved;
}

static NSFont *self_resolveFont(int fontId, CGFloat size)
{
	NSString *family = familyForId(fontId);
	if (!family || family.length == 0) return [NSFont systemFontOfSize:size];
	// CSS system-font keywords map to the actual system UI font — San Francisco
	// on macOS. There is no PostScript face literally named "-apple-system", so
	// `+[NSFont fontWithName:@"-apple-system"]` returns nil and we'd otherwise
	// fall through to a wrong family. systemFontOfSize: IS San Francisco.
	NSString *lower = family.lowercaseString;
	if ([lower isEqualToString:@"-apple-system"] || [lower isEqualToString:@"system-ui"] ||
	    [lower isEqualToString:@"blinkmacsystemfont"] || [lower hasPrefix:@".applesystemuifont"] ||
	    [lower hasPrefix:@".sf"] || [lower isEqualToString:@"san francisco"] ||
	    [lower isEqualToString:@"sf pro"] || [lower isEqualToString:@"sf pro text"]) {
		return [NSFont systemFontOfSize:size];
	}
	NSFont *font = [NSFont fontWithName:family size:size];
	if (font) return font;
	// CTFont's family lookup is more forgiving than NSFont's PostScript-name
	// lookup — fall back to building a CTFont with the family attribute.
	NSDictionary *attrs = @{
		(__bridge NSString *)kCTFontFamilyNameAttribute: family,
		(__bridge NSString *)kCTFontSizeAttribute: @(size),
	};
	CTFontDescriptorRef desc = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attrs);
	CTFontRef ct = CTFontCreateWithFontDescriptor(desc, size, NULL);
	CFRelease(desc);
	if (ct) {
		NSFont *resolved = (__bridge_transfer NSFont *)ct;
		return resolved;
	}
	return [NSFont systemFontOfSize:size];
}

int registerCustomTtfDirectory(NSString *directoryPath)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:directoryPath isDirectory:&isDir] || !isDir) return 0;
	NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:directoryPath error:nil];
	int count = 0;
	for (NSString *name in entries) {
		NSString *lower = name.lowercaseString;
		if (![lower hasSuffix:@".ttf"] && ![lower hasSuffix:@".otf"]) continue;
		NSString *path = [directoryPath stringByAppendingPathComponent:name];
		registerTtfBytesForFamily(path);
		CFErrorRef err = NULL;
		CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
		if (CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, &err)) {
			count++;
		} else if (err) {
			NSError *e = (__bridge_transfer NSError *)err;
			// kCTFontManagerErrorAlreadyRegistered == 105 — fine on rebuilds.
			if (e.code != 105) {
				NSLog(@"[gea] failed to register font %@: %@", name, e.localizedDescription);
			}
		}
	}
	return count;
}

}  // namespace gea::macos

// Strong overrides of the framework's weak font-lookup hooks for the AppKit
// renderer. The Thermalright target uses Gea's generated raster font atlas
// instead, so these host-font overrides must stay out of that build.
#if !GEA_MACOS_THERMALRIGHT_DISPLAY_TARGET
namespace gea::framework::graphics::generated {

int lookupFontFamily(const char *family)
{
	if (!family || !family[0]) return -1;
	return gea::macos::registerFamily(std::string(family));
}

const RasterizedFontData *lookupFontForFamily(int, int) { return nullptr; }
const RasterizedFontData *lookupFont(int) { return nullptr; }
void ensureLinked() {}

// Feeds the engine's runtime TTF rasterizer (canvas ctx.fillText). AppKit
// text nodes never come through here — they resolve native NSFonts via
// fontForId above.
const std::uint8_t *lookupRuntimeTtfFontForFamily(int familyId, unsigned long *length)
{
	return gea::macos::runtimeTtfBytesForFamilyId(familyId, length);
}

}  // namespace gea::framework::graphics::generated
#endif

namespace gea::macos {

// Choose a line-break mode that breaks AT word boundaries when possible,
// falling back to mid-character when an unbreakable run is wider than the
// available width. The renderer and the measurement path share this logic
// so AppKit's render geometry always matches the framework's measurement.
NSLineBreakMode lineBreakModeForText(NSString *text, NSFont *font, CGFloat maxWidth)
{
	if (maxWidth <= 0 || text.length == 0 || !font) return NSLineBreakByWordWrapping;
	NSDictionary *probeAttrs = @{ NSFontAttributeName: font };
	// Split on whitespace and check each chunk individually. If even one
	// "word" wouldn't fit on a line by itself, word-wrap can't help us —
	// we'd render that word overflowing the field width and the parent
	// tile's overflow:hidden would clip it mid-glyph with no indication.
	// Char-wrap breaks inside the word so all of it stays visible.
	NSArray<NSString *> *chunks = [text componentsSeparatedByCharactersInSet:
	    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	for (NSString *chunk in chunks) {
		if (chunk.length == 0) continue;
		CGFloat chunkWidth = [chunk sizeWithAttributes:probeAttrs].width;
		if (chunkWidth > maxWidth) return NSLineBreakByCharWrapping;
	}
	return NSLineBreakByWordWrapping;
}

}  // namespace gea::macos

// Host text-measurement hook for the AppKit renderer. The Thermalright target
// has no AppKit text renderer; it wants the framework's generated-font metrics.
#if !GEA_MACOS_THERMALRIGHT_DISPLAY_TARGET
extern "C" bool gea_host_measure_text(const char *text,
                                      int maxWidth,
                                      int fontId,
                                      int fontSize,
                                      int *outWidth,
                                      int *outHeight)
{
	if (!outWidth || !outHeight) return false;
	if (!text || !text[0]) {
		*outWidth = 0;
		*outHeight = 0;
		return true;
	}

	// Memoize by (text, maxWidth, fontId, fontSize): the layout engine re-measures
	// EVERY text node on EVERY layout pass, and a pass now runs on every
	// interaction. NSTextFieldCell.cellSizeForBounds:/sizeWithAttributes:
	// dominated the interaction profile; the inputs fully determine the result,
	// so a cache turns repeat measurements (the stable note list) into O(1).
	static std::mutex measureLock;
	static std::unordered_map<std::string, std::pair<int, int>> measureCache;
	std::string key;
	key.reserve(std::strlen(text) + 24);
	key.append(text);
	key.push_back('\x1f');
	key.append(std::to_string(maxWidth));
	key.push_back('\x1f');
	key.append(std::to_string(fontId));
	key.push_back('\x1f');
	key.append(std::to_string(fontSize));
	{
		std::scoped_lock guard(measureLock);
		auto it = measureCache.find(key);
		if (it != measureCache.end()) {
			*outWidth = it->second.first;
			*outHeight = it->second.second;
			return true;
		}
	}

	NSFont *font = gea::macos::fontForId(fontId, fontSize);
	if (!font) return false;
	NSString *str = [NSString stringWithUTF8String:text] ?: @"";
	const CGFloat boundedMax = maxWidth > 0 ? maxWidth : CGFLOAT_MAX;
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.lineBreakMode = gea::macos::lineBreakModeForText(str, font, boundedMax);
	NSDictionary *attrs = @{
		NSFontAttributeName: font,
		NSParagraphStyleAttributeName: paragraph,
	};
	NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:str attributes:attrs];
	// Use an actual NSTextFieldCell to measure: this is exactly what the
	// renderer's NSTextField uses to lay text out, so the size we report
	// here is the size AppKit will draw into — no off-by-side-bearing,
	// no kerning surprise, no device-metrics vs typographic gap. Sizing
	// against a fresh cell of size (maxWidth, large) returns the wrapped
	// height + the actual line width AppKit needs.
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
	cell.bezeled = NO;
	cell.bordered = NO;
	cell.drawsBackground = NO;
	cell.wraps = YES;
	cell.attributedStringValue = attributed;
	const NSSize cellSize = [cell cellSizeForBounds:NSMakeRect(0, 0, boundedMax, CGFLOAT_MAX)];
	*outWidth = static_cast<int>(std::ceil(cellSize.width));
	*outHeight = static_cast<int>(std::ceil(cellSize.height));
	{
		std::scoped_lock guard(measureLock);
		if (measureCache.size() > 8192) measureCache.clear();  // bound unbounded growth
		measureCache.emplace(std::move(key), std::make_pair(*outWidth, *outHeight));
	}
	return true;
}
#endif

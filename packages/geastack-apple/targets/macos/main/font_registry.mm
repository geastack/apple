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

static NSFont *self_resolveFont(int fontId, int sizePx, int weight, int stretch)
{
	NSString *family = familyForId(fontId);
	const CGFloat size = std::clamp(sizePx > 0 ? sizePx : 13, 1, 4096);
	if (!family || family.length == 0) return [NSFont systemFontOfSize:size];
	NSString *lower = family.lowercaseString;
	if ([lower isEqualToString:@"-apple-system"] || [lower isEqualToString:@"system-ui"] ||
	    [lower isEqualToString:@"blinkmacsystemfont"] || [lower hasPrefix:@".applesystemuifont"] ||
	    [lower hasPrefix:@".sf"] || [lower isEqualToString:@"san francisco"] ||
	    [lower isEqualToString:@"sf pro"] || [lower isEqualToString:@"sf pro text"]) {
		const CGFloat nativeWeight = weight <= 400 ? (weight - 400) / 1000.0 : (weight - 400) / 800.0;
		return [NSFont systemFontOfSize:size weight:nativeWeight];
	}
	NSDictionary *baseAttributes = @{ (__bridge NSString *)kCTFontFamilyNameAttribute: family };
	CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)baseAttributes);
	CTFontRef base = CTFontCreateWithFontDescriptor(descriptor, size, nullptr);
	CFRelease(descriptor);
	if (!base) return [NSFont systemFontOfSize:size];
	NSMutableDictionary *variation = [NSMutableDictionary dictionary];
	CFArrayRef axes = CTFontCopyVariationAxes(base);
	if (axes) {
		for (NSDictionary *axis in (__bridge NSArray *)axes) {
			NSNumber *identifier = axis[(__bridge NSString *)kCTFontVariationAxisIdentifierKey];
			const uint32_t tag = identifier.unsignedIntValue;
			if (tag != 0x77676874 && tag != 0x77647468) continue; // wght / wdth
			const double requested = tag == 0x77676874 ? weight : stretch / 10.0;
			const double minimum = [axis[(__bridge NSString *)kCTFontVariationAxisMinimumValueKey] doubleValue];
			const double maximum = [axis[(__bridge NSString *)kCTFontVariationAxisMaximumValueKey] doubleValue];
			variation[identifier] = @(std::clamp(requested, minimum, maximum));
		}
		CFRelease(axes);
	}
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	if (variation.count) attributes[(__bridge NSString *)kCTFontVariationAttribute] = variation;
	else attributes[(__bridge NSString *)kCTFontTraitsAttribute] = @{
		(__bridge NSString *)kCTFontWeightTrait: @((weight - 400) / 800.0)
	};
	CTFontDescriptorRef adjustment = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
	CTFontRef selected = CTFontCreateCopyWithAttributes(base, size, nullptr, adjustment);
	CFRelease(adjustment); CFRelease(base);
	return selected ? (__bridge_transfer NSFont *)selected : [NSFont systemFontOfSize:size];
}

NSFont *fontForId(int fontId, int sizePx, int weight, int stretch)
{
	weight = std::clamp(weight, 1, 1000);
	stretch = std::clamp(stretch, 1, 32767);
	sizePx = std::clamp(sizePx > 0 ? sizePx : 13, 1, 4096);
	static NSMutableDictionary<NSString *, NSFont *> *cache = [NSMutableDictionary dictionary];
	NSString *key = [NSString stringWithFormat:@"%d:%d:%d:%d", fontId, sizePx, weight, stretch];
	@synchronized(cache) { NSFont *hit = cache[key]; if (hit) return hit; }
	NSFont *selected = self_resolveFont(fontId, sizePx, weight, stretch);
	if (selected) { @synchronized(cache) { if (cache.count >= 1024) [cache removeAllObjects]; cache[key] = selected; } }
	return selected;
}

NSFont *fontForId(int fontId, int sizePx) { return fontForId(fontId, sizePx, 400, 1000); }

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
static bool measureNativeText(const char *text,
                                      int maxWidth,
                                      int fontId,
                                      int fontSize, int fontWeight, int fontStretch, int lineHeight,
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
	key.push_back('\x1f'); key.append(std::to_string(fontWeight));
	key.push_back('\x1f'); key.append(std::to_string(fontStretch));
	key.push_back('\x1f'); key.append(std::to_string(lineHeight));
	{
		std::scoped_lock guard(measureLock);
		auto it = measureCache.find(key);
		if (it != measureCache.end()) {
			*outWidth = it->second.first;
			*outHeight = it->second.second;
			return true;
		}
	}

	NSFont *font = gea::macos::fontForId(fontId, fontSize, fontWeight, fontStretch);
	if (!font) return false;
	NSString *str = [NSString stringWithUTF8String:text] ?: @"";
	const CGFloat boundedMax = maxWidth > 0 ? maxWidth : CGFLOAT_MAX;
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.lineBreakMode = gea::macos::lineBreakModeForText(str, font, boundedMax);
	if (lineHeight > 0) { paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight; }
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
// Readiness must reject CoreText's successful system fallback for a missing face.
extern "C" bool gea_host_packaged_font_available(int familyId)
{
 unsigned long length = 0;
 if (!gea::macos::runtimeTtfBytesForFamilyId(familyId, &length) || !length) return false;
 NSString *requested = gea::macos::familyForId(familyId);
 NSFont *selected = gea::macos::fontForId(familyId, 14, 400, 1000);
 if (!requested || !selected || ![selected.familyName isEqualToString:requested]) return false;
 const UniChar characters[] = {'A', 0x00b5};
 CGGlyph glyphs[2] = {};
 return CTFontGetGlyphsForCharacters((__bridge CTFontRef)selected, characters, glyphs, 2)
   && glyphs[0] != 0 && glyphs[1] != 0;
}
extern "C" bool gea_host_measure_text(const char *text, int maxWidth, int fontId, int fontSize, int *width, int *height)
{ return measureNativeText(text, maxWidth, fontId, fontSize, 400, 1000, 0, width, height); }
extern "C" bool gea_host_measure_text_with_style(const char *text, int maxWidth, int fontId, int fontSize, int weight, int lineHeight, int *width, int *height)
{ return measureNativeText(text, maxWidth, fontId, fontSize, weight, 1000, lineHeight, width, height); }
extern "C" bool gea_host_measure_text_with_variations(const char *text, int maxWidth, int fontId, int fontSize, int weight, int stretch, int lineHeight, int *width, int *height)
{ return measureNativeText(text, maxWidth, fontId, fontSize, weight, stretch, lineHeight, width, height); }
#endif

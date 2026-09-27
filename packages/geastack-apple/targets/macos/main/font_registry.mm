#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>

#include "font_registry.h"
#include "graphics/font.h"
#include "ui/style.h"

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

static NSFont *self_resolveFont(int fontId, CGFloat size, int weight);

namespace {

// CSS font-weight → CoreText's normalised weight trait (the NSFontWeight*
// constants: 400 Regular = 0, 600 Semibold = 0.3, 700 Bold = 0.4, ...).
CGFloat coreTextWeightForCss(int weight)
{
	if (weight <= 100) return NSFontWeightUltraLight;
	if (weight <= 200) return NSFontWeightThin;
	if (weight <= 300) return NSFontWeightLight;
	if (weight <= 400) return NSFontWeightRegular;
	if (weight <= 500) return NSFontWeightMedium;
	if (weight <= 600) return NSFontWeightSemibold;
	if (weight <= 700) return NSFontWeightBold;
	if (weight <= 800) return NSFontWeightHeavy;
	return NSFontWeightBlack;
}

CGFloat weightTraitOf(NSFont *font)
{
	NSDictionary *traits = (__bridge_transfer NSDictionary *)CTFontCopyTraits((__bridge CTFontRef)font);
	return [traits[(__bridge NSString *)kCTFontWeightTrait] doubleValue];
}

// Between Medium (0.23) and Semibold (0.3): CSS's bold threshold is 600.
constexpr CGFloat kBoldWeightTrait = 0.26;

bool isBoldWeight(int weight) { return weight >= 600; }

// The face of `base`'s family closest to the CSS weight, or `base` when the
// family has nothing nearer. A CSS bold (>= 600) that CoreText resolves to a
// lighter face (Helvetica Neue has Medium but no Semibold) takes the family's
// bold face instead, the way the CSS matching algorithm looks heavier first.
NSFont *faceForWeight(NSFont *base, CGFloat size, int weight)
{
	if (!base || weight <= 0 || weight == 400) return base;
	NSDictionary *attrs = @{
		(__bridge NSString *)kCTFontFamilyNameAttribute: base.familyName ?: @"",
		(__bridge NSString *)kCTFontTraitsAttribute: @{(__bridge NSString *)kCTFontWeightTrait: @(coreTextWeightForCss(weight))},
	};
	CTFontDescriptorRef wanted = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attrs);
	NSSet *mandatory = [NSSet setWithObject:(__bridge NSString *)kCTFontFamilyNameAttribute];
	CTFontDescriptorRef matched = CTFontDescriptorCreateMatchingFontDescriptor(wanted, (__bridge CFSetRef)mandatory);
	CFRelease(wanted);
	NSFont *face = base;
	if (matched) {
		face = (__bridge_transfer NSFont *)CTFontCreateWithFontDescriptor(matched, size, NULL) ?: base;
		CFRelease(matched);
	}
	if (isBoldWeight(weight) && weightTraitOf(face) < kBoldWeightTrait) {
		CTFontRef bold = CTFontCreateCopyWithSymbolicTraits((__bridge CTFontRef)base, size, NULL, kCTFontTraitBold, kCTFontTraitBold);
		if (bold) face = (__bridge_transfer NSFont *)bold;
	}
	return face;
}

// Skia's fake-bold outset (SkScalerContext kStdFakeBoldInterp*), which is what
// Chrome paints a CSS bold with when the family ships no bold face: the outline
// is stroked and filled with a pen of size * k, k running from 1/24 at 9px to
// 1/32 at 36px. The advances stay those of the regular face.
CGFloat fakeBoldPenScale(CGFloat cssSize)
{
	const CGFloat t = std::clamp((cssSize - 9.0) / (36.0 - 9.0), 0.0, 1.0);
	return 1.0 / 24.0 + t * (1.0 / 32.0 - 1.0 / 24.0);
}

struct ResolvedFace {
	NSFont *font = nil;
	CGFloat syntheticBoldStroke = 0;  // NSStrokeWidthAttributeName, 0 = a real face
};

const ResolvedFace &resolveFace(int fontId, int sizePx, int weight)
{
	CGFloat size = sizePx > 0 ? static_cast<CGFloat>(sizePx) : [NSFont systemFontSize];
	const int cssWeight = weight > 0 ? std::min(weight, 1000) : 400;  // 0 = unset = normal

	// Cache resolved fonts by (fontId, size, weight). `+[NSFont fontWithName:size:]`
	// and the CTFontDescriptor matches below are expensive — and this is called
	// for EVERY text node on EVERY frame (renderer sync + layout measurement).
	// Without this cache, CoreText font matching dominated the profile and pegged
	// a CPU core. The set of (family, size, weight) an app uses is tiny, so the
	// cache stays small.
	static std::mutex lock;
	static std::unordered_map<long long, ResolvedFace> cache;
	const long long key = (static_cast<long long>(fontId + 1) * 1001LL + cssWeight) * 100000LL + llround(size);
	std::scoped_lock guard(lock);
	auto it = cache.find(key);
	if (it != cache.end()) return it->second;
	ResolvedFace face;
	face.font = self_resolveFont(fontId, size, cssWeight);
	// A bold the family has no face for is synthesised, as a browser does: the
	// regular outlines stroked in their own colour (a negative stroke width is
	// stroke AND fill). Weather ships Oswald Regular alone; without this every
	// 600/700 label painted regular.
	if (face.font && isBoldWeight(cssWeight) && weightTraitOf(face.font) < kBoldWeightTrait) {
		const double ratio = gea::embedded::ui::devicePixelRatio();
		const CGFloat cssSize = ratio > 0 ? size / ratio : size;
		face.syntheticBoldStroke = -100.0 * fakeBoldPenScale(cssSize);
	}
	return cache.emplace(key, face).first->second;
}

}  // namespace

NSFont *fontForId(int fontId, int sizePx, int weight)
{
	return resolveFace(fontId, sizePx, weight).font;
}

CGFloat syntheticBoldStrokeWidth(int fontId, int sizePx, int weight)
{
	return resolveFace(fontId, sizePx, weight).syntheticBoldStroke;
}

void addSyntheticBold(NSMutableDictionary *attrs, int fontId, int sizePx, int weight)
{
	const CGFloat stroke = syntheticBoldStrokeWidth(fontId, sizePx, weight);
	// No stroke colour: AppKit strokes in the foreground colour, alpha included.
	if (stroke != 0) attrs[NSStrokeWidthAttributeName] = @(stroke);
}

static NSFont *self_resolveFont(int fontId, CGFloat size, int weight)
{
	NSString *family = familyForId(fontId);
	if (!family || family.length == 0) return [NSFont systemFontOfSize:size weight:coreTextWeightForCss(weight)];
	// CSS system-font keywords map to the actual system UI font — San Francisco
	// on macOS. There is no PostScript face literally named "-apple-system", so
	// `+[NSFont fontWithName:@"-apple-system"]` returns nil and we'd otherwise
	// fall through to a wrong family. systemFontOfSize: IS San Francisco.
	NSString *lower = family.lowercaseString;
	if ([lower isEqualToString:@"-apple-system"] || [lower isEqualToString:@"system-ui"] ||
	    [lower isEqualToString:@"blinkmacsystemfont"] || [lower hasPrefix:@".applesystemuifont"] ||
	    [lower hasPrefix:@".sf"] || [lower isEqualToString:@"san francisco"] ||
	    [lower isEqualToString:@"sf pro"] || [lower isEqualToString:@"sf pro text"]) {
		return [NSFont systemFontOfSize:size weight:coreTextWeightForCss(weight)];
	}
	NSFont *font = [NSFont fontWithName:family size:size];
	if (font) return faceForWeight(font, size, weight);
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
		return faceForWeight(resolved, size, weight);
	}
	return [NSFont systemFontOfSize:size weight:coreTextWeightForCss(weight)];
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
// The engine offers three hooks and takes the first that answers; this one
// carries the font-weight the other two drop, so a 600 label is measured in the
// face (or the synthesised bold) the renderer paints it with.
extern "C" bool gea_host_measure_text_with_style(const char *text,
                                                 int maxWidth,
                                                 int fontId,
                                                 int fontSize,
                                                 int fontWeight,
                                                 int lineHeight,
                                                 int *outWidth,
                                                 int *outHeight)
{
	if (!outWidth || !outHeight) return false;
	if (!text || !text[0]) {
		*outWidth = 0;
		*outHeight = 0;
		return true;
	}

	// Memoize by (text, maxWidth, fontId, fontSize, fontWeight, lineHeight): the
	// layout engine re-measures EVERY text node on EVERY layout pass, and a pass
	// now runs on every interaction. NSTextFieldCell.cellSizeForBounds:/
	// sizeWithAttributes: dominated the interaction profile; the inputs fully
	// determine the result, so a cache turns repeat measurements (the stable note
	// list) into O(1).
	static std::mutex measureLock;
	static std::unordered_map<std::string, std::pair<int, int>> measureCache;
	std::string key;
	key.reserve(std::strlen(text) + 32);
	key.append(text);
	key.push_back('\x1f');
	key.append(std::to_string(maxWidth));
	key.push_back('\x1f');
	key.append(std::to_string(fontId));
	key.push_back('\x1f');
	key.append(std::to_string(fontSize));
	key.push_back('\x1f');
	key.append(std::to_string(fontWeight));
	key.push_back('\x1f');
	key.append(std::to_string(lineHeight));
	{
		std::scoped_lock guard(measureLock);
		auto it = measureCache.find(key);
		if (it != measureCache.end()) {
			*outWidth = it->second.first;
			*outHeight = it->second.second;
			return true;
		}
	}

	NSFont *font = gea::macos::fontForId(fontId, fontSize, fontWeight);
	if (!font) return false;
	NSString *str = [NSString stringWithUTF8String:text] ?: @"";
	const CGFloat boundedMax = maxWidth > 0 ? maxWidth : CGFLOAT_MAX;
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.lineBreakMode = gea::macos::lineBreakModeForText(str, font, boundedMax);
	// CSS `line-height` sets the LINE BOX height, which is what the engine stacks
	// text rows with. Without it AppKit reports the font's own default leading and
	// every text node measures taller than the stylesheet says — weather's hour
	// cells came out 46% too tall and overflowed the forecast box. Pinning min ==
	// max makes the cell report lines * lineHeight, which is the CSS box.
	if (lineHeight > 0) {
		paragraph.minimumLineHeight = lineHeight;
		paragraph.maximumLineHeight = lineHeight;
	}
	NSMutableDictionary *attrs = [@{
		NSFontAttributeName: font,
		NSParagraphStyleAttributeName: paragraph,
	} mutableCopy];
	gea::macos::addSyntheticBold(attrs, fontId, fontSize, fontWeight);
	NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:str attributes:attrs];
	// Use an actual NSTextFieldCell to measure: this is exactly what the
	// renderer's NSTextField uses to lay text out, so the size we report
	// here is the size AppKit will draw into — no off-by-side-bearing,
	// no kerning surprise, no device-metrics vs typographic gap. Sizing
	// against a fresh cell of size (maxWidth, large) returns the wrapped
	// height + the actual line width AppKit needs.
	//
	// Less the cell's side insets (kLabelSideInset): they are not part of the
	// CSS text box, and reporting them made every label 4pt wider than a
	// browser's — weather's "Lisbon 22°" chip grew a gap between its two runs.
	// The cell is offered the insets on top of maxWidth so it still wraps at
	// maxWidth; the renderer's field gets them back (applyViewStyle).
	const CGFloat insets = 2 * gea::macos::kLabelSideInset;
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
	cell.bezeled = NO;
	cell.bordered = NO;
	cell.drawsBackground = NO;
	cell.wraps = YES;
	cell.attributedStringValue = attributed;
	const NSSize cellSize = [cell cellSizeForBounds:NSMakeRect(0, 0, maxWidth > 0 ? boundedMax + insets : CGFLOAT_MAX, CGFLOAT_MAX)];
	*outWidth = std::max(0, static_cast<int>(std::ceil(cellSize.width - insets)));
	*outHeight = static_cast<int>(std::ceil(cellSize.height));
	{
		std::scoped_lock guard(measureLock);
		if (measureCache.size() > 8192) measureCache.clear();  // bound unbounded growth
		measureCache.emplace(std::move(key), std::make_pair(*outWidth, *outHeight));
	}
	return true;
}

extern "C" bool gea_host_measure_text_with_line_height(const char *text,
                                                       int maxWidth,
                                                       int fontId,
                                                       int fontSize,
                                                       int lineHeight,
                                                       int *outWidth,
                                                       int *outHeight)
{
	return gea_host_measure_text_with_style(text, maxWidth, fontId, fontSize, 400, lineHeight, outWidth, outHeight);
}
#endif

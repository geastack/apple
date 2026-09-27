#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "font_registry.h"
#include "graphics/font.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <mutex>
#include <unordered_map>

namespace gea::ios {
namespace {

std::once_flag g_registerFontsOnce;

void registerFontURL(NSURL *url)
{
	if (!url) return;
	CFErrorRef err = NULL;
	if (CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &err)) return;
	if (!err) return;
	NSError *error = CFBridgingRelease(err);
	if (error.code != kCTFontManagerErrorAlreadyRegistered) {
		NSLog(@"[gea] failed to register font %@: %@", url.lastPathComponent, error.localizedDescription);
	}
}

void registerBundledFontsWithExtension(NSString *extension)
{
	NSArray<NSURL *> *urls = [[NSBundle mainBundle] URLsForResourcesWithExtension:extension subdirectory:nil];
	NSArray<NSURL *> *fontURLs = urls ?: @[];
	for (NSURL *url in fontURLs) registerFontURL(url);
}

void ensureBundledFontsRegistered()
{
	std::call_once(g_registerFontsOnce, [] {
		registerBundledFontsWithExtension(@"ttf");
		registerBundledFontsWithExtension(@"otf");
	});
}

UIFont *fontFromPostScriptNameForFamily(NSString *family, CGFloat size)
{
	NSDictionary *attrs = @{
		(__bridge NSString *)kCTFontFamilyNameAttribute: family,
		(__bridge NSString *)kCTFontSizeAttribute: @(size),
	};
	CTFontDescriptorRef desc = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attrs);
	CTFontRef ct = CTFontCreateWithFontDescriptor(desc, size, NULL);
	CFRelease(desc);
	if (!ct) return nil;

	CFStringRef psName = CTFontCopyPostScriptName(ct);
	CFRelease(ct);
	if (!psName) return nil;

	UIFont *font = [UIFont fontWithName:(__bridge NSString *)psName size:size];
	CFRelease(psName);
	return font;
}

// CSS font-weight → CoreText's normalised weight trait (the UIFontWeight*
// constants: 400 Regular = 0, 600 Semibold = 0.3, 700 Bold = 0.4, ...).
CGFloat coreTextWeightForCss(int weight)
{
	if (weight <= 100) return UIFontWeightUltraLight;
	if (weight <= 200) return UIFontWeightThin;
	if (weight <= 300) return UIFontWeightLight;
	if (weight <= 400) return UIFontWeightRegular;
	if (weight <= 500) return UIFontWeightMedium;
	if (weight <= 600) return UIFontWeightSemibold;
	if (weight <= 700) return UIFontWeightBold;
	if (weight <= 800) return UIFontWeightHeavy;
	return UIFontWeightBlack;
}

CGFloat weightTraitOf(UIFont *font)
{
	NSDictionary *traits = (__bridge_transfer NSDictionary *)CTFontCopyTraits((__bridge CTFontRef)font);
	return [traits[(__bridge NSString *)kCTFontWeightTrait] doubleValue];
}

// Between Medium (0.23) and Semibold (0.3): CSS's bold threshold is 600.
constexpr CGFloat kBoldWeightTrait = 0.26;

bool isBoldWeight(int weight) { return weight >= 600; }

// The face of `family` nearest the CSS weight, upright before italic. UIKit
// lists a family's faces in no particular order, so taking the first one could
// hand a regular label the family's Bold or Italic. As in the CSS matching
// algorithm, a weight above 500 looks heavier first and any other lighter first.
UIFont *faceForWeight(NSString *family, CGFloat size, int weight)
{
	const CGFloat wanted = coreTextWeightForCss(weight);
	const bool heavierFirst = weight > 500;
	UIFont *best = nil;
	CGFloat bestScore = CGFLOAT_MAX;
	for (NSString *fontName in [UIFont fontNamesForFamilyName:family]) {
		UIFont *font = [UIFont fontWithName:fontName size:size];
		if (!font) continue;
		const CGFloat trait = weightTraitOf(font);
		const bool wrongWay = heavierFirst ? trait < wanted : trait > wanted;
		const bool italic = (font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0;
		const CGFloat score = std::fabs(trait - wanted) + (wrongWay ? 2.0 : 0.0) + (italic ? 4.0 : 0.0);
		if (score < bestScore) {
			best = font;
			bestScore = score;
		}
	}
	return best;
}

UIFont *fontForFamily(NSString *family, CGFloat size, int weight)
{
	if (!family || family.length == 0) return nil;

	UIFont *face = faceForWeight(family, size, weight);
	if (face) return face;

	UIFont *direct = [UIFont fontWithName:family size:size];
	if (direct) return direct;

	return fontFromPostScriptNameForFamily(family, size);
}

// Skia's fake-bold outset (SkScalerContext kStdFakeBoldInterp*), which is what
// Chrome paints a CSS bold with when the family ships no bold face: the outline
// is stroked and filled with a pen of size * k, k running from 1/24 at 9px to
// 1/32 at 36px. The advances stay those of the regular face.
CGFloat fakeBoldPenScale(CGFloat cssSize)
{
	const CGFloat t = std::clamp<CGFloat>((cssSize - 9.0) / (36.0 - 9.0), 0.0, 1.0);
	return 1.0 / 24.0 + t * (1.0 / 32.0 - 1.0 / 24.0);
}

struct ResolvedFace {
	UIFont *font = nil;
	CGFloat syntheticBoldStroke = 0;  // NSStrokeWidthAttributeName, 0 = a real face
};

const ResolvedFace &resolveFace(int fontId, CGFloat sizePt, int weight)
{
	const CGFloat size = sizePt > 0 ? sizePt : [UIFont systemFontSize];
	const int cssWeight = weight > 0 ? std::min(weight, 1000) : 400;  // 0 = unset = normal
	ensureBundledFontsRegistered();

	// Every label asks on every frame, from the renderer sync and from layout
	// measurement, and a family lookup instantiates each of the family's faces
	// to read its weight. An app uses a handful of (family, size, weight)
	// combinations, so the cache stays small.
	static std::mutex lock;
	static std::unordered_map<long long, ResolvedFace> cache;
	const long long key = ((static_cast<long long>(fontId) + 1) * 1001LL + cssWeight) * 1000000LL + std::llround(size * 64.0);
	std::scoped_lock guard(lock);
	auto it = cache.find(key);
	if (it != cache.end()) return it->second;

	const char *familyName = gea::framework::graphics::FontRegistry::familyName(fontId);
	NSString *family = familyName && familyName[0] ? [NSString stringWithUTF8String:familyName] : nil;
	ResolvedFace face;
	face.font = fontForFamily(family, size, cssWeight) ?: [UIFont systemFontOfSize:size weight:coreTextWeightForCss(cssWeight)];
	// A bold the family has no face for is synthesised, as a browser does: the
	// regular outlines stroked in their own colour (a negative stroke width is
	// stroke AND fill). Weather ships Oswald Regular alone; without this every
	// 600/700 label painted regular.
	if (isBoldWeight(cssWeight) && weightTraitOf(face.font) < kBoldWeightTrait) {
		const double ratio = gea::embedded::ui::devicePixelRatio();
		const CGFloat cssSize = ratio > 0 ? size / ratio : size;
		face.syntheticBoldStroke = -100.0 * fakeBoldPenScale(cssSize);
	}
	return cache.emplace(key, face).first->second;
}

}  // namespace

UIFont *fontForId(int fontId, CGFloat sizePt, int weight)
{
	return resolveFace(fontId, sizePt, weight).font;
}

CGFloat syntheticBoldStrokeWidth(int fontId, CGFloat sizePt, int weight)
{
	return resolveFace(fontId, sizePt, weight).syntheticBoldStroke;
}

void addSyntheticBold(NSMutableDictionary *attrs, int fontId, CGFloat sizePt, int weight)
{
	const CGFloat stroke = syntheticBoldStrokeWidth(fontId, sizePt, weight);
	// No stroke colour: UIKit strokes in the foreground colour, alpha included.
	if (attrs && stroke != 0) attrs[NSStrokeWidthAttributeName] = @(stroke);
}

}  // namespace gea::ios

// The engine offers three hooks and takes the first that answers; this one
// carries the font-weight the other two drop, so a 600 label is measured in the
// face the renderer paints it with. A synthesised bold is only stroked, which
// moves no advance, so it measures as its regular face -- as it does in a
// browser. CSS `line-height` is the LINE BOX height the engine stacks rows
// with, and UIKit otherwise reports the font's own leading -- every text node
// then measures taller than the stylesheet says.
extern "C" bool gea_host_measure_text_with_style(const char *text,
                                                 int maxWidth,
                                                 int fontId,
                                                 int fontSize,
                                                 int fontWeight,
                                                 int lineHeight,
                                                 int *outWidth,
                                                 int *outHeight)
{
	if (!outWidth || !outHeight || fontId < 0) return false;
	if (!text || !text[0]) {
		*outWidth = 0;
		*outHeight = 0;
		return true;
	}

	@autoreleasepool {
		UIFont *font = gea::ios::fontForId(fontId, fontSize, fontWeight);
		if (!font) return false;

		NSString *str = [NSString stringWithUTF8String:text] ?: @"";
		NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
		paragraph.lineBreakMode = NSLineBreakByWordWrapping;
		if (lineHeight > 0) {
			paragraph.minimumLineHeight = lineHeight;
			paragraph.maximumLineHeight = lineHeight;
		}
		NSDictionary *attrs = @{
			NSFontAttributeName: font,
			NSParagraphStyleAttributeName: paragraph,
		};

		UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
		label.numberOfLines = 0;
		label.lineBreakMode = NSLineBreakByWordWrapping;
		label.attributedText = [[NSAttributedString alloc] initWithString:str attributes:attrs];
		const CGFloat boundedMax = maxWidth > 0 ? static_cast<CGFloat>(maxWidth) : CGFLOAT_MAX;
		const CGSize measured = [label sizeThatFits:CGSizeMake(boundedMax, CGFLOAT_MAX)];
		*outWidth = static_cast<int>(std::ceil(measured.width) + 1.0);
		// Exactly that many px per line, as win32 reports it: the extra px the
		// natural case keeps as slack made every short-line label (weather's 1.0
		// and 1.1 rows) one px taller than CSS, and the rows below it drift.
		if (lineHeight > 0) {
			const int lines = std::max(1, static_cast<int>(std::lround(measured.height / lineHeight)));
			*outHeight = lines * lineHeight;
		} else {
			*outHeight = static_cast<int>(std::ceil(measured.height) + 1.0);
		}
		return true;
	}
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

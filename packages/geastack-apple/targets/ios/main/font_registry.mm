#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "font_registry.h"
#include "graphics/font.h"

#include <cmath>
#include <mutex>

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

UIFont *fontForFamily(NSString *family, CGFloat size)
{
	if (!family || family.length == 0) return nil;

	for (NSString *fontName in [UIFont fontNamesForFamilyName:family]) {
		UIFont *font = [UIFont fontWithName:fontName size:size];
		if (font) return font;
	}

	UIFont *direct = [UIFont fontWithName:family size:size];
	if (direct) return direct;

	return fontFromPostScriptNameForFamily(family, size);
}

}  // namespace

UIFont *fontForId(int fontId, CGFloat sizePt)
{
	const CGFloat size = sizePt > 0 ? sizePt : [UIFont systemFontSize];
	ensureBundledFontsRegistered();

	const char *familyName = gea::framework::graphics::FontRegistry::familyName(fontId);
	NSString *family = familyName && familyName[0] ? [NSString stringWithUTF8String:familyName] : nil;
	UIFont *font = fontForFamily(family, size);
	return font ?: [UIFont systemFontOfSize:size];
}

}  // namespace gea::ios

extern "C" bool gea_host_measure_text(const char *text,
                                      int maxWidth,
                                      int fontId,
                                      int fontSize,
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
		UIFont *font = gea::ios::fontForId(fontId, fontSize);
		if (!font) return false;

		NSString *str = [NSString stringWithUTF8String:text] ?: @"";
		NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
		paragraph.lineBreakMode = NSLineBreakByWordWrapping;
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
		*outHeight = static_cast<int>(std::ceil(measured.height) + 1.0);
		return true;
	}
}

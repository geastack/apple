#include "ios_renderer_internal.h"

#include "font_registry.h"
#include "graphics/font.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

@implementation GeaNativeLabel

- (void)drawRect:(CGRect)rect
{
	if (!self.geaUseBitmapFont) {
		[super drawRect:rect];
		return;
	}
	(void)rect;
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (!ctx) return;

	const CGFloat pixel = std::max<CGFloat>(1.0, self.geaBitmapGlyphScale);
	const CGFloat glyphW = gea::framework::graphics::BitmapFont8x16::kWidth * pixel;
	const CGFloat glyphH = gea::framework::graphics::BitmapFont8x16::kHeight * pixel;
	if (glyphW <= 0 || glyphH <= 0) return;

	std::string text = self.geaBitmapText ? self.geaBitmapText.UTF8String : "";
	const std::size_t maxChars = std::max<std::size_t>(1, static_cast<std::size_t>(std::floor(self.bounds.size.width / glyphW)));
	std::vector<std::string> lines;
	std::string line;
	for (unsigned char c : text) {
		if (c == '\r') continue;
		if (c == '\n') {
			lines.push_back(line);
			line.clear();
			continue;
		}
		if (line.size() >= maxChars) {
			lines.push_back(line);
			line.clear();
		}
		line.push_back(c >= 0x20 && c <= 0x7e ? static_cast<char>(c) : '?');
	}
	lines.push_back(line);

	UIColor *color = self.geaBitmapColor ?: UIColor.whiteColor;
	[color setFill];
	const auto &font = gea::framework::graphics::BitmapFont8x16::instance();
	for (std::size_t lineIndex = 0; lineIndex < lines.size(); lineIndex++) {
		const std::string &textLine = lines[lineIndex];
		const CGFloat lineWidth = static_cast<CGFloat>(textLine.size()) * glyphW;
		CGFloat penX = 0;
		if (self.textAlignment == NSTextAlignmentCenter) {
			penX = std::max<CGFloat>(0, (self.bounds.size.width - lineWidth) / 2.0);
		} else if (self.textAlignment == NSTextAlignmentRight) {
			penX = std::max<CGFloat>(0, self.bounds.size.width - lineWidth);
		}
		const CGFloat lineStartX = penX;
		const CGFloat penY = static_cast<CGFloat>(lineIndex) * glyphH;
		if (penY >= self.bounds.size.height) break;
		for (unsigned char c : textLine) {
			const std::uint8_t *rows = font.glyphRows(static_cast<char>(c));
			for (int row = 0; row < gea::framework::graphics::BitmapFont8x16::kHeight; row++) {
				for (int col = 0; col < gea::framework::graphics::BitmapFont8x16::kWidth; col++) {
					if ((rows[row] & (0x80 >> col)) == 0) continue;
					CGContextFillRect(ctx, CGRectMake(penX + static_cast<CGFloat>(col) * pixel,
					                                  penY + static_cast<CGFloat>(row) * pixel,
					                                  pixel,
					                                  pixel));
				}
			}
			penX += glyphW;
		}
		const CGFloat thickness = std::max<CGFloat>(1.0, std::ceil(pixel));
		if (self.geaBitmapTextDecoration == 1) {
			CGContextFillRect(ctx, CGRectMake(lineStartX, penY + glyphH * 0.88, lineWidth, thickness));
		} else if (self.geaBitmapTextDecoration == 2) {
			CGContextFillRect(ctx, CGRectMake(lineStartX, penY + glyphH * 0.58, lineWidth, thickness));
		}
	}
}

@end

namespace gea::ios::renderer {

// CSS `line-height` sets the LINE BOX, not a clip. When it is shorter than the
// font's natural line -- Oswald's is 1.48em and weather asks for 0.75 to 1.1 --
// the glyphs overflow the box and still paint. A UILabel draws inside its
// bounds, so the CSS-sized box sheared the bottoms off `.temp`'s 54px digits and
// every descender on a 1.0 line. Give the label the extra leading it needs,
// centred on the box the engine allocated (CSS centres each glyph run in its
// line box), so the painting surface matches CSS while the layout position does
// not move -- macOS does the same for its text fields. A box that clips its own
// overflow keeps its size: CSS cuts those glyphs too.
CGRect textPaintFrame(const gea::embedded::ui::Node &node, CGRect frame, CGFloat scale)
{
	if (node.style.font_id < 0 || node.style.line_height <= 0 || node.style.overflow != 0) return frame;
	if (frame.size.height <= 0) return frame;
	const CGFloat fontSize = std::max<CGFloat>(1.0, static_cast<CGFloat>(node.style.font_size > 0 ? node.style.font_size : 16) * scale);
	UIFont *font = gea::ios::fontForId(node.style.font_id, fontSize, node.style.font_weight);
	if (!font) return frame;
	const CGFloat lineBox = static_cast<CGFloat>(node.style.line_height) * scale;
	const int lines = std::max(1, static_cast<int>(std::lround(frame.size.height / lineBox)));
	const CGFloat needed = font.lineHeight * lines;
	if (needed <= frame.size.height) return frame;
	return CGRectInset(frame, 0, -(needed - frame.size.height) / 2.0);
}

void applyTextProps(GeaNativeLabel *label, const gea::embedded::ui::Node &node, CGFloat scale)
{
	NSString *raw = NSStringFromText(node.text);
	const CGFloat fontSize = std::max<CGFloat>(1.0, static_cast<CGFloat>(node.style.font_size > 0 ? node.style.font_size : 16) * scale);
	UIColor *color = rgb565ToUIColor(node.style.text_color, node.style.text_alpha);
	label.textAlignment = textAlignmentForStyle(node.style.text_align);
	// `white-space: nowrap` keeps the run on one line, and `text-overflow:
	// ellipsis` (only consulted then, as in CSS) cuts it at the box with "...".
	// Every label used to wrap whatever it was given, so weather's chip names,
	// capped at 64px, broke onto a second line inside a one-line box.
	const bool noWrap = node.style.white_space == 1;
	const NSLineBreakMode lineBreak = !noWrap ? NSLineBreakByWordWrapping
	                                  : node.style.text_overflow == 1 ? NSLineBreakByTruncatingTail
	                                                                  : NSLineBreakByClipping;
	label.numberOfLines = noWrap ? 1 : 0;
	if (node.style.font_id < 0) {
		label.geaUseBitmapFont = YES;
		label.geaBitmapText = raw;
		label.geaBitmapColor = color;
		label.geaBitmapGlyphScale = fontSize / gea::framework::graphics::BitmapFont8x16::kHeight;
		label.geaBitmapTextDecoration = node.style.text_decoration;
		label.attributedText = nil;
		label.text = nil;
		label.font = [UIFont systemFontOfSize:fontSize];
		label.textColor = color;
		[label setNeedsDisplay];
		return;
	}

	label.geaUseBitmapFont = NO;
	label.geaBitmapText = nil;
	label.geaBitmapColor = nil;
	UIFont *font = gea::ios::fontForId(node.style.font_id, fontSize, node.style.font_weight);
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.alignment = textAlignmentForStyle(node.style.text_align);
	paragraph.lineBreakMode = lineBreak;
	// Only ever GROWS the line box — see the same note in macOS applyTextProps.
	// The measurement hook pins min == max so the engine gets the CSS line box;
	// doing that when drawing clips descenders instead, which CSS never does.
	// `font` is sized in scaled points, so the CSS line box is scaled the same
	// way before the two are compared (textPaintFrame does the same). Comparing
	// the unscaled value gave the label a smaller line box than the one measured
	// and painted whenever scale != 1, which is every phone.
	const CGFloat lineBox = static_cast<CGFloat>(node.style.line_height) * scale;
	if (font && node.style.line_height > 0 && lineBox > font.ascender - font.descender) paragraph.minimumLineHeight = lineBox;
	NSMutableDictionary *attrs = textAttributes(font, color, node.style.text_decoration);
	attrs[NSParagraphStyleAttributeName] = paragraph;
	gea::ios::addSyntheticBold(attrs, node.style.font_id, fontSize, node.style.font_weight);
	label.attributedText = [[NSAttributedString alloc] initWithString:raw attributes:attrs];
	label.font = font;
	label.textColor = color;
	label.lineBreakMode = lineBreak;
	[label setNeedsDisplay];
}

}  // namespace gea::ios::renderer

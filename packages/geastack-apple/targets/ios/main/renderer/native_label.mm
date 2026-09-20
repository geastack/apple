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
namespace {

void fitNativeButtonLabelIfNeeded(GeaNativeLabel *label)
{
	if (!label || ![label.superview isKindOfClass:[GeaNativeButton class]] || label.geaUseBitmapFont) return;
	if (label.attributedText.length == 0) return;

	const CGSize nativeSize = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	if (nativeSize.width <= 0 || nativeSize.height <= 0) return;

	UIView *button = label.superview;
	const CGRect bounds = button.bounds;
	CGRect frame = label.frame;
	const CGFloat nextWidth = std::ceil(nativeSize.width) + 1.0;
	const CGFloat nextHeight = std::ceil(nativeSize.height) + 1.0;
	if (nextWidth > frame.size.width) {
		const CGFloat centerX = CGRectGetMidX(frame);
		frame.size.width = nextWidth;
		frame.origin.x = centerX - nextWidth / 2.0;
		if (bounds.size.width > 0 && nextWidth <= bounds.size.width) {
			frame.origin.x = std::clamp<CGFloat>(frame.origin.x, 0, bounds.size.width - nextWidth);
		}
	}
	if (nextHeight > frame.size.height) {
		const CGFloat centerY = CGRectGetMidY(frame);
		frame.size.height = nextHeight;
		frame.origin.y = centerY - nextHeight / 2.0;
		if (bounds.size.height > 0 && nextHeight <= bounds.size.height) {
			frame.origin.y = std::clamp<CGFloat>(frame.origin.y, 0, bounds.size.height - nextHeight);
		}
	}
	label.frame = frame;
}

}  // namespace

void applyTextProps(GeaNativeLabel *label, const gea::embedded::ui::Node &node, CGFloat scale)
{
	NSString *raw = NSStringFromText(node.text);
	const CGFloat fontSize = std::max<CGFloat>(1.0, static_cast<CGFloat>(node.style.font_size > 0 ? node.style.font_size : 16) * scale);
	UIColor *color = rgb565ToUIColor(node.style.text_color);
	label.geaHostedByNativeButtonTitle = [label.superview isKindOfClass:[GeaNativeButton class]];
	label.hidden = label.geaHostedByNativeButtonTitle;
	label.textAlignment = textAlignmentForStyle(node.style.text_align);
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
	UIFont *font = gea::ios::fontForId(node.style.font_id, fontSize);
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.alignment = textAlignmentForStyle(node.style.text_align);
	paragraph.lineBreakMode = NSLineBreakByWordWrapping;
	NSMutableDictionary *attrs = textAttributes(font, color, node.style.text_decoration);
	attrs[NSParagraphStyleAttributeName] = paragraph;
	label.attributedText = [[NSAttributedString alloc] initWithString:raw attributes:attrs];
	label.font = font;
	label.textColor = color;
	fitNativeButtonLabelIfNeeded(label);
	[label setNeedsDisplay];
}

}  // namespace gea::ios::renderer

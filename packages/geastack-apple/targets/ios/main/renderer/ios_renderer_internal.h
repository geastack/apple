#pragma once

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include "ui/node_model.h"

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

@class GeaCanvasView;

@interface GeaNativeLabel : UILabel
@property(nonatomic, assign) BOOL geaUseBitmapFont;
@property(nonatomic, copy) NSString *geaBitmapText;
@property(nonatomic, strong) UIColor *geaBitmapColor;
@property(nonatomic, assign) CGFloat geaBitmapGlyphScale;
@property(nonatomic, assign) NSInteger geaBitmapTextDecoration;
@end

@interface GeaNativeButton : UIButton
@property(nonatomic, assign) int nodeId;
- (void)handleTouchDown:(id)sender;
- (void)handleTouchDrag:(id)sender;
- (void)handleTouchUpInside:(id)sender;
- (void)handleTouchUpOutside:(id)sender;
- (void)handleTouchCancel:(id)sender;
@end

@interface GeaNativeScrollContainer : UIScrollView <UIScrollViewDelegate>
@property(nonatomic, assign) int nodeId;
@property(nonatomic, assign) BOOL syncingFromTree;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UILabel *debugTelemetryLabel;
@property(nonatomic, strong) UILabel *debugTopMarkerLabel;
@property(nonatomic, strong) UILabel *debugBottomMarkerLabel;
@property(nonatomic, assign) CGFloat minObservedContentOffsetY;
@property(nonatomic, assign) CGFloat maxObservedContentOffsetY;
- (void)updateScrollTelemetryWithScale:(CGFloat)scale;
- (void)commitNativeScrollTopWithScale:(CGFloat)scale;
// Vertical offsets: the native one and the most it can be.
- (CGFloat)geaMaxOffset;
- (CGFloat)geaRawOffset;
@end

namespace gea::ios::renderer {

// A style colour is an OPAQUE packed pixel — the CSS alpha rides beside it in a
// separate style field (bg_alpha, text_alpha, border_alpha, …), because RGB565
// has no alpha channel and the style system keeps one representation for every
// board. Pass the matching field or translucent CSS paints solid.
UIColor *rgb565ToUIColor(gea::framework::graphics::pixel::native_t color, std::uint8_t alpha = 255);
CGFloat canvasScaleForView(UIView *view);
void dispatchSyntheticTap(UIView *rootView, CGPoint point);
bool isScrollableNode(const gea::embedded::ui::Node &node);
// Sets the layer's cornerRadius/maskedCorners from the node's CSS border-radius
// at its current layout size.
void applyCornerRadius(CALayer *layer, const gea::embedded::ui::Node &node, CGFloat scale);
// Reorders `parent`'s subviews into stacking order; `children` is (z-index, view)
// in DOM order.
void stackChildViews(UIView *parent, std::vector<std::pair<int, UIView *>> &children);
NSMutableDictionary<NSNumber *, UIView *> *nodeIdToView();
NSString *NSStringFromText(const std::string &value);
NSTextAlignment textAlignmentForStyle(int align);
NSMutableDictionary *textAttributes(UIFont *font, UIColor *color, int textDecoration);

void applyTextProps(GeaNativeLabel *label, const gea::embedded::ui::Node &node, CGFloat scale);
// The frame a text node's label paints in: its layout box, grown to fit glyphs
// that overflow a short CSS line box (see native_label.mm).
CGRect textPaintFrame(const gea::embedded::ui::Node &node, CGRect frame, CGFloat scale);
void applyButtonProps(GeaNativeButton *button, const gea::embedded::ui::Node &node, int nodeId);
void applyScrollProps(GeaNativeScrollContainer *scrollView,
                      const gea::embedded::ui::Node &node,
                      int nodeId,
                      CGFloat scale);

void syncNativeTree(UIView *parentForRoot, int rootNodeId);
void teardownNativeTree();
bool hasNativeTree();

}  // namespace gea::ios::renderer

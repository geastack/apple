#pragma once

#import <UIKit/UIKit.h>

#include "ui/node_model.h"

#include <cstdint>
#include <string>

@class GeaCanvasView;

@interface GeaNativeLabel : UILabel
@property(nonatomic, assign) BOOL geaUseBitmapFont;
@property(nonatomic, copy) NSString *geaBitmapText;
@property(nonatomic, strong) UIColor *geaBitmapColor;
@property(nonatomic, assign) CGFloat geaBitmapGlyphScale;
@property(nonatomic, assign) NSInteger geaBitmapTextDecoration;
@property(nonatomic, assign) BOOL geaHostedByNativeButtonTitle;
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
@end

namespace gea::ios::renderer {

UIColor *rgb565ToUIColor(gea::framework::graphics::pixel::native_t color);
CGFloat canvasScaleForView(UIView *view);
void dispatchSyntheticTap(UIView *rootView, CGPoint point);
bool isScrollableNode(const gea::embedded::ui::Node &node);
NSMutableDictionary<NSNumber *, UIView *> *nodeIdToView();
NSString *NSStringFromText(const std::string &value);
NSTextAlignment textAlignmentForStyle(int align);
NSMutableDictionary *textAttributes(UIFont *font, UIColor *color, int textDecoration);

void applyTextProps(GeaNativeLabel *label, const gea::embedded::ui::Node &node, CGFloat scale);
void applyButtonProps(GeaNativeButton *button, const gea::embedded::ui::Node &node, int nodeId, CGFloat scale);
void applyScrollProps(GeaNativeScrollContainer *scrollView,
                      const gea::embedded::ui::Node &node,
                      int nodeId,
                      CGFloat scale);

void syncNativeTree(UIView *parentForRoot, int rootNodeId);
void teardownNativeTree();
bool hasNativeTree();

}  // namespace gea::ios::renderer

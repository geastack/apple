#include "ios_renderer_internal.h"

#include "ui/tree_internal.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace gea::ios::renderer {
namespace {

bool scrollDebugMarkersEnabled()
{
	static int cached = -1;
	if (cached >= 0) return cached == 1;
	bool enabled = false;
	const char *env = std::getenv("GEA_IOS_SCROLL_DEBUG_MARKERS");
	if (env && env[0] && std::strcmp(env, "0") != 0 && std::strcmp(env, "false") != 0) enabled = true;
	for (NSString *arg in NSProcessInfo.processInfo.arguments) {
		if ([arg isEqualToString:@"--gea-scroll-debug-markers"]) {
			enabled = true;
			break;
		}
	}
	cached = enabled ? 1 : 0;
	return enabled;
}

UILabel *makeScrollDebugLabel(NSString *identifier, UIColor *background)
{
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
	label.accessibilityIdentifier = identifier;
	label.isAccessibilityElement = YES;
	label.backgroundColor = background;
	label.textColor = UIColor.whiteColor;
	label.numberOfLines = 2;
	label.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightSemibold];
	label.textAlignment = NSTextAlignmentLeft;
	label.userInteractionEnabled = NO;
	label.layer.cornerRadius = 4.0;
	label.clipsToBounds = YES;
	return label;
}

bool nearlyEqual(CGFloat a, CGFloat b)
{
	return std::fabs(a - b) <= 0.5;
}

bool rectNearlyEqual(CGRect a, CGRect b)
{
	return nearlyEqual(a.origin.x, b.origin.x) &&
	       nearlyEqual(a.origin.y, b.origin.y) &&
	       nearlyEqual(a.size.width, b.size.width) &&
	       nearlyEqual(a.size.height, b.size.height);
}

}  // namespace
}  // namespace gea::ios::renderer

@implementation GeaNativeScrollContainer

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_nodeId = -1;
		_syncingFromTree = NO;
		_minObservedContentOffsetY = CGFLOAT_MAX;
		_maxObservedContentOffsetY = -CGFLOAT_MAX;
		self.delegate = self;
		self.backgroundColor = UIColor.clearColor;
		self.opaque = NO;
		self.clipsToBounds = YES;
		self.isAccessibilityElement = YES;
		self.accessibilityIdentifier = @"gea-native-scroll";
		self.bounces = YES;
		self.alwaysBounceVertical = YES;
		self.alwaysBounceHorizontal = NO;
		self.directionalLockEnabled = YES;
		self.decelerationRate = UIScrollViewDecelerationRateNormal;
		self.showsVerticalScrollIndicator = NO;
		self.showsHorizontalScrollIndicator = NO;
		self.delaysContentTouches = NO;
		self.canCancelContentTouches = YES;
		self.scrollsToTop = NO;
		if (@available(iOS 11.0, *)) self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		_contentView = [[UIView alloc] initWithFrame:CGRectZero];
		_contentView.userInteractionEnabled = NO;
		_contentView.backgroundColor = UIColor.clearColor;
		[self addSubview:_contentView];
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
		tap.cancelsTouchesInView = NO;
		[self addGestureRecognizer:tap];
	}
	return self;
}

- (void)ensureDebugMarkers
{
	if (!gea::ios::renderer::scrollDebugMarkersEnabled()) return;
	if (!self.debugTelemetryLabel) {
		self.debugTelemetryLabel = gea::ios::renderer::makeScrollDebugLabel(
		    @"gea-scroll-telemetry", [UIColor colorWithRed:0.02 green:0.04 blue:0.08 alpha:0.86]);
		[self addSubview:self.debugTelemetryLabel];
	}
	if (!self.debugTopMarkerLabel) {
		self.debugTopMarkerLabel = gea::ios::renderer::makeScrollDebugLabel(
		    @"gea-scroll-content-top-marker", [UIColor colorWithRed:0.85 green:0.10 blue:0.10 alpha:0.82]);
		self.debugTopMarkerLabel.text = @" content y=0";
		[self.contentView addSubview:self.debugTopMarkerLabel];
	}
	if (!self.debugBottomMarkerLabel) {
		self.debugBottomMarkerLabel = gea::ios::renderer::makeScrollDebugLabel(
		    @"gea-scroll-content-bottom-marker", [UIColor colorWithRed:0.10 green:0.42 blue:0.95 alpha:0.82]);
		[self.contentView addSubview:self.debugBottomMarkerLabel];
	}
}

- (void)layoutDebugMarkers
{
	if (!gea::ios::renderer::scrollDebugMarkersEnabled()) return;
	[self ensureDebugMarkers];
	const CGFloat visibleX = self.contentOffset.x + 8.0;
	const CGFloat visibleY = self.contentOffset.y + 8.0;
	const CGFloat markerWidth = std::max<CGFloat>(160.0, self.bounds.size.width - 16.0);
	self.debugTelemetryLabel.frame = CGRectMake(visibleX, visibleY, markerWidth, 42.0);
	const CGFloat contentWidth = std::max<CGFloat>(self.contentSize.width, self.bounds.size.width);
	self.debugTopMarkerLabel.frame = CGRectMake(0, 0, contentWidth, 24.0);
	const CGFloat bottomY = std::max<CGFloat>(28.0, self.contentSize.height - 28.0);
	self.debugBottomMarkerLabel.frame = CGRectMake(0, bottomY, contentWidth, 28.0);
	[self bringSubviewToFront:self.debugTelemetryLabel];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	[self layoutDebugMarkers];
}

- (void)updateScrollTelemetryWithScale:(CGFloat)scale
{
	if (self.nodeId < 0) return;
	const CGFloat rawY = self.contentOffset.y;
	if (rawY < self.minObservedContentOffsetY) self.minObservedContentOffsetY = rawY;
	if (rawY > self.maxObservedContentOffsetY) self.maxObservedContentOffsetY = rawY;

	auto &tree = gea::embedded::ui::Tree::instance();
	const int treeY = self.nodeId < tree.nodeCount() ? tree.scrollTop(self.nodeId) : 0;
	const CGFloat maxY = std::max<CGFloat>(0, self.contentSize.height - self.bounds.size.height);
	const CGFloat overTop = std::min<CGFloat>(0, rawY);
	const CGFloat overBottom = std::max<CGFloat>(0, rawY - maxY);
	const CGFloat visualContentY = self.contentView.frame.origin.y - rawY;
	NSString *value = [NSString stringWithFormat:@"node=%d rawY=%.2f treeY=%d maxY=%.2f minRawY=%.2f maxRawY=%.2f overTop=%.2f overBottom=%.2f visualY=%.2f scale=%.3f tracking=%d dragging=%d decel=%d",
	                   self.nodeId, rawY, treeY, maxY, self.minObservedContentOffsetY, self.maxObservedContentOffsetY,
	                   overTop, overBottom, visualContentY, scale, self.tracking ? 1 : 0, self.dragging ? 1 : 0,
	                   self.decelerating ? 1 : 0];
	self.accessibilityValue = value;

	if (gea::ios::renderer::scrollDebugMarkersEnabled()) {
		[self ensureDebugMarkers];
		self.debugTelemetryLabel.text = [NSString stringWithFormat:@"rawY=%.1f treeY=%d maxY=%.1f\nmin=%.1f max=%.1f over=%.1f/%.1f",
		                                 rawY, treeY, maxY, self.minObservedContentOffsetY,
		                                 self.maxObservedContentOffsetY, overTop, overBottom];
		self.debugTelemetryLabel.accessibilityValue = value;
		self.debugBottomMarkerLabel.text = [NSString stringWithFormat:@" content y=max %.0f", maxY];
		[self layoutDebugMarkers];
	}
}

- (void)commitNativeScrollTopWithScale:(CGFloat)scale
{
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;

	const CGFloat maxOffset = std::max<CGFloat>(0, self.contentSize.height - self.bounds.size.height);
	const CGFloat rawOffset = self.contentOffset.y;
	if (rawOffset < -0.5 || rawOffset > maxOffset + 0.5) {
		[self updateScrollTelemetryWithScale:scale];
		return;
	}

	const CGFloat logicalOffset = std::clamp(rawOffset, static_cast<CGFloat>(0), maxOffset);
	const int before = tree.scrollTop(self.nodeId);
	const int next = static_cast<int>(std::lround(logicalOffset / std::max<CGFloat>(scale, 0.0001)));
	tree.setScrollTop(self.nodeId, next);
	if (tree.scrollTop(self.nodeId) != before && tree.mountedRoot() >= 0) {
		tree.refresh(tree.mountedRoot(), tree.mountedWidth(), tree.mountedHeight());
	}
	[self updateScrollTelemetryWithScale:scale];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer
{
	if (recognizer.state != UIGestureRecognizerStateEnded) return;
	gea::ios::renderer::dispatchSyntheticTap(self.superview, [recognizer locationInView:self.superview]);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	if (self.nodeId < 0) return;
	(void)scrollView;
	const CGFloat scale = gea::ios::renderer::canvasScaleForView(self.superview);
	if (self.syncingFromTree) {
		[self updateScrollTelemetryWithScale:scale];
		return;
	}
	const CGFloat maxOffset = std::max<CGFloat>(0, scrollView.contentSize.height - scrollView.bounds.size.height);
	const CGFloat rawOffset = scrollView.contentOffset.y;
	const BOOL nativeScrollActive = scrollView.tracking || scrollView.dragging || scrollView.decelerating;
	const BOOL rubberBanding = rawOffset < -0.5 || rawOffset > maxOffset + 0.5;
	if (nativeScrollActive || rubberBanding) {
		[self updateScrollTelemetryWithScale:scale];
		return;
	}
	[self commitNativeScrollTopWithScale:scale];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	(void)scrollView;
	if (decelerate) return;
	[self commitNativeScrollTopWithScale:gea::ios::renderer::canvasScaleForView(self.superview)];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
	(void)scrollView;
	[self commitNativeScrollTopWithScale:gea::ios::renderer::canvasScaleForView(self.superview)];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
	(void)scrollView;
	[self commitNativeScrollTopWithScale:gea::ios::renderer::canvasScaleForView(self.superview)];
}

@end

namespace gea::ios::renderer {

void applyScrollProps(GeaNativeScrollContainer *scrollView,
                      const gea::embedded::ui::Node &node,
                      int nodeId,
                      CGFloat scale)
{
	scrollView.nodeId = nodeId;
	const CGFloat w = static_cast<CGFloat>(node.layout.width) * scale;
	const CGFloat h = static_cast<CGFloat>(std::max<int>(node.layout.height, node.layout.scroll_content_height)) * scale;
	const CGSize nextContentSize = CGSizeMake(w, h);
	if (std::fabs(scrollView.contentSize.width - nextContentSize.width) > 0.5 ||
	    std::fabs(scrollView.contentSize.height - nextContentSize.height) > 0.5) {
		scrollView.contentSize = nextContentSize;
	}
	const CGRect nextContentFrame = CGRectMake(0, 0, w, h);
	if (!rectNearlyEqual(scrollView.contentView.frame, nextContentFrame)) scrollView.contentView.frame = nextContentFrame;
	scrollView.hidden = node.style.display == 1 || node.style.opacity == 0;
	scrollView.userInteractionEnabled = !scrollView.hidden;

	const CGFloat maxOffset = std::max<CGFloat>(0, scrollView.contentSize.height - scrollView.bounds.size.height);
	const CGFloat rawOffset = scrollView.contentOffset.y;
	const BOOL nativeScrollActive = scrollView.tracking || scrollView.dragging || scrollView.decelerating;
	const BOOL rubberBanding = rawOffset < -0.5 || rawOffset > maxOffset + 0.5;
	if (!nativeScrollActive && !rubberBanding) {
		const CGFloat desired = std::clamp(static_cast<CGFloat>(gea::embedded::ui::Tree::instance().scrollTop(nodeId)) * scale,
		                                   static_cast<CGFloat>(0),
		                                   maxOffset);
		if (std::fabs(scrollView.contentOffset.y - desired) > 0.5) {
			scrollView.syncingFromTree = YES;
			scrollView.contentOffset = CGPointMake(0, desired);
			scrollView.syncingFromTree = NO;
		}
	}
	[scrollView updateScrollTelemetryWithScale:scale];
}

}  // namespace gea::ios::renderer

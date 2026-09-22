#import <QuartzCore/QuartzCore.h>

#include "ios_renderer_internal.h"
#include "canvas_view.h"
#include "image_bridge.h"

#include "ui/tree_internal.h"
#include "ui/style.h"

#import <objc/runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>

namespace gea::ios::renderer {
namespace {

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

bool viewMatchesNode(UIView *view, const gea::embedded::ui::Node &node, const char *tagName)
{
	using gea::embedded::ui::NodeType;
	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "input") == 0) return false;
	if (isScrollableNode(node)) return [view isKindOfClass:[GeaNativeScrollContainer class]];
	switch (node.type) {
	case NodeType::Text: return [view isKindOfClass:[GeaNativeLabel class]];
	case NodeType::Button: return [view isKindOfClass:[GeaNativeButton class]];
	case NodeType::Image: return [view isKindOfClass:[UIImageView class]];
	case NodeType::Canvas: return [view isKindOfClass:[GeaCanvasView class]];
	default: return [view isKindOfClass:[UIView class]] &&
	                ![view isKindOfClass:[UILabel class]] &&
	                ![view isKindOfClass:[UIControl class]] &&
	                ![view isKindOfClass:[UIImageView class]] &&
	                ![view isKindOfClass:[UIScrollView class]] &&
	                ![view isKindOfClass:[GeaCanvasView class]];
	}
}

UIView *makeViewForType(gea::embedded::ui::NodeType type, const char *tagName,
                        const gea::embedded::ui::Node &node)
{
	using gea::embedded::ui::NodeType;
	if (type == NodeType::View && tagName && std::strcmp(tagName, "input") == 0) return nil;
	if (isScrollableNode(node)) return [[GeaNativeScrollContainer alloc] initWithFrame:CGRectZero];
	switch (type) {
	case NodeType::Text: {
		GeaNativeLabel *label = [[GeaNativeLabel alloc] initWithFrame:CGRectZero];
		label.numberOfLines = 0;
		label.lineBreakMode = NSLineBreakByWordWrapping;
		label.userInteractionEnabled = NO;
		label.backgroundColor = UIColor.clearColor;
		return label;
	}
	case NodeType::Image: {
		UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
		imageView.userInteractionEnabled = NO;
		return imageView;
	}
	case NodeType::Canvas: return [[GeaCanvasView alloc] initWithFrame:CGRectZero];
	case NodeType::Button: {
		GeaNativeButton *button = [GeaNativeButton buttonWithType:UIButtonTypeCustom];
		button.nodeId = -1;
		button.backgroundColor = UIColor.clearColor;
		button.opaque = NO;
		[button setTitle:nil forState:UIControlStateNormal];
		[button addTarget:button action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
		[button addTarget:button action:@selector(handleTouchDrag:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
		[button addTarget:button action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
		[button addTarget:button action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];
		[button addTarget:button action:@selector(handleTouchCancel:) forControlEvents:UIControlEventTouchCancel];
		return button;
	}
	case NodeType::View:
	case NodeType::VirtualList:
	default: {
		UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
		view.userInteractionEnabled = NO;
		return view;
	}
	}
}

void applyViewStyle(UIView *view, const gea::embedded::ui::Node &node,
                    int parentAbsX, int parentAbsY, CGFloat scale)
{
	const CGFloat x = static_cast<CGFloat>(node.layout.x - parentAbsX) * scale;
	const CGFloat y = static_cast<CGFloat>(node.layout.y - parentAbsY) * scale;
	const CGFloat w = static_cast<CGFloat>(node.layout.width) * scale;
	const CGFloat h = static_cast<CGFloat>(node.layout.height) * scale;

	// UIKit's `frame` is undefined while a non-identity transform is applied, and a
	// transform always rotates about the layer's anchor point (center) rather than
	// the CSS transform-origin. Re-feeding `frame` every animation frame under a
	// live rotation corrupts the bounds, ballooning rotated nodes (e.g. clock
	// hands). For rotated nodes drive geometry through bounds + center + anchorPoint
	// so the size stays correct and the rotation pivots about transform-origin;
	// otherwise keep the plain frame path that scroll containers rely on.
	if ((gea::embedded::ui::rstyle(node.style).transform_rotate % 3600) != 0) {
		const CGFloat originX = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_origin_x) / 1000.0;
		const CGFloat originY = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_origin_y) / 1000.0;
		const CGPoint anchor = CGPointMake(originX, originY);
		if (!CGPointEqualToPoint(view.layer.anchorPoint, anchor)) view.layer.anchorPoint = anchor;
		if (!nearlyEqual(view.bounds.size.width, w) || !nearlyEqual(view.bounds.size.height, h)) {
			CGRect bounds = view.bounds;
			bounds.size = CGSizeMake(w, h);
			view.bounds = bounds;
		}
		const CGPoint center = CGPointMake(x + originX * w, y + originY * h);
		if (!nearlyEqual(view.center.x, center.x) || !nearlyEqual(view.center.y, center.y)) {
			view.center = center;
		}
		const CGFloat degrees = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_rotate) / 10.0;
		view.transform = CGAffineTransformMakeRotation(degrees * static_cast<CGFloat>(M_PI / 180.0));
	} else {
		if (!CGAffineTransformIsIdentity(view.transform)) view.transform = CGAffineTransformIdentity;
		if (!CGPointEqualToPoint(view.layer.anchorPoint, CGPointMake(0.5, 0.5))) {
			view.layer.anchorPoint = CGPointMake(0.5, 0.5);
		}
		const CGRect nextFrame = CGRectMake(x, y, w, h);
		if (!rectNearlyEqual(view.frame, nextFrame)) view.frame = nextFrame;
	}
	view.hidden = node.style.display == 1 || node.style.opacity == 0 || w <= 0 || h <= 0;
	view.alpha = static_cast<CGFloat>(node.style.opacity) / 255.0;

	// view.alpha above is ELEMENT opacity and fades the subtree with it; a
	// background's own alpha must not go through it, or the labels sitting on a
	// translucent chip fade too. It belongs to the colour.
	view.backgroundColor = node.style.has_bg ? rgb565ToUIColor(node.style.bg_color, node.style.bg_alpha)
	                                         : UIColor.clearColor;
	view.layer.borderWidth = static_cast<CGFloat>(std::max<int>(0, node.style.border_width)) * scale;
	view.layer.borderColor = rgb565ToUIColor(node.style.border_color, node.style.border_alpha).CGColor;
	const int tl = std::max<int>(0, node.style.border_radius[0]);
	const int tr = std::max<int>(0, node.style.border_radius[1]);
	const int br = std::max<int>(0, node.style.border_radius[2]);
	const int bl = std::max<int>(0, node.style.border_radius[3]);
	const CGFloat radius = (tl == tr && tr == br && br == bl)
	                           ? static_cast<CGFloat>(tl)
	                           : static_cast<CGFloat>(tl + tr + br + bl) / 4.0;
	view.layer.cornerRadius = radius * scale;
	view.clipsToBounds = view.layer.cornerRadius > 0 || node.style.overflow == 1 || node.style.overflow == 2;
}

void applyImageProps(UIImageView *imageView, const gea::embedded::ui::Node &node)
{
	NSNumber *currentId = objc_getAssociatedObject(imageView, "gea.image_id");
	if (!currentId || currentId.intValue != node.image_id) {
		imageView.image = gea::ios::imageForId(node.image_id);
		objc_setAssociatedObject(imageView, "gea.image_id", @(node.image_id), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	switch (node.style.image_fit) {
	case 1: imageView.contentMode = UIViewContentModeScaleAspectFit; break;
	case 2: imageView.contentMode = UIViewContentModeScaleAspectFill; break;
	case 3: imageView.contentMode = UIViewContentModeCenter; break;
	case 4: imageView.contentMode = UIViewContentModeScaleAspectFit; break;
	default: imageView.contentMode = UIViewContentModeScaleToFill;
	}
	imageView.clipsToBounds = YES;
}

void applyCanvasProps(GeaCanvasView *canvasView, int nodeId)
{
	canvasView.nodeId = nodeId;
	[canvasView setNeedsDisplay];
}

void applyTypeSpecificProps(UIView *view, const gea::embedded::ui::Node &node, int nodeId, CGFloat scale)
{
	using gea::embedded::ui::NodeType;
	if ([view isKindOfClass:[GeaNativeScrollContainer class]]) {
		applyScrollProps((GeaNativeScrollContainer *)view, node, nodeId, scale);
	} else if (node.type == NodeType::Button) {
		applyButtonProps((GeaNativeButton *)view, node, nodeId, scale);
	} else if (node.type == NodeType::Text) {
		applyTextProps((GeaNativeLabel *)view, node, scale);
	} else if (node.type == NodeType::Image) {
		applyImageProps((UIImageView *)view, node);
	} else if (node.type == NodeType::Canvas) {
		applyCanvasProps((GeaCanvasView *)view, nodeId);
	}
}

UIView *ensureViewForNode(int nodeId, const gea::embedded::ui::Node &node)
{
	auto &tree = gea::embedded::ui::Tree::instance();
	NSNumber *key = @(nodeId);
	UIView *view = nodeIdToView()[key];
	const char *tagName = tree.tagName(nodeId);
	if (view && !viewMatchesNode(view, node, tagName)) {
		[view removeFromSuperview];
		[nodeIdToView() removeObjectForKey:key];
		view = nil;
	}
	if (view) return view;
	view = makeViewForType(node.type, tagName, node);
	if (!view) return nil;
	objc_setAssociatedObject(view, "gea.node_id", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	nodeIdToView()[key] = view;
	return view;
}

void syncRecursive(int nodeId, UIView *parent, int parentAbsX, int parentAbsY, CGFloat scale,
                   NSMutableSet<NSNumber *> *unseen)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return;
	const Node &node = tree.node(nodeId);
	const char *tagName = tree.tagName(nodeId);
	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "input") == 0) return;

	NSNumber *key = @(nodeId);
	[unseen removeObject:key];
	UIView *view = ensureViewForNode(nodeId, node);
	if (!view) return;
	if (view.superview != parent) {
		[view removeFromSuperview];
		[parent addSubview:view];
	}
	applyViewStyle(view, node, parentAbsX, parentAbsY, scale);
	applyTypeSpecificProps(view, node, nodeId, scale);

	UIView *parentForChildren = view;
	int parentAbsXForChildren = node.layout.x;
	int parentAbsYForChildren = node.layout.y;
	if ([view isKindOfClass:[GeaNativeScrollContainer class]]) {
		parentForChildren = ((GeaNativeScrollContainer *)view).contentView;
		parentAbsYForChildren = node.layout.y - tree.scrollTop(nodeId);
	}

	for (int child = node.first_child; child >= 0; child = tree.node(child).next_sibling) {
		syncRecursive(child, parentForChildren, parentAbsXForChildren, parentAbsYForChildren, scale, unseen);
	}
}

}  // namespace

// GEA_IOS_LAYOUT_DUMP=1 prints what the engine computed next to what this file
// turned it into, which is the only way to tell a layout bug from a reconciler
// bug without a debugger. macOS has had the same thing (GEA_MACOS_LAYOUT_DUMP);
// iOS had no introspection at all. First few frames, then every 60th, so a
// "correct on frame 1, wrong on frame 2" pattern is visible.
void dumpLayout(UIView *parentForRoot, int rootNodeId)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	static int dumpFrame = 0;
	++dumpFrame;
	if (dumpFrame > 5 && dumpFrame % 60 != 0) return;

	NSLog(@"[gea-layout] frame=%d root=%d host=%@ dpr=%.3f", dumpFrame, rootNodeId,
	      NSStringFromCGRect(parentForRoot.bounds), devicePixelRatio());
	for (int i = 0; i < tree.nodeCount(); i++) {
		const auto &n = tree.node(i);
		const std::string cls = tree.className(i);
		NSLog(@"  node[%d] parent=%d t=%d class=\"%s\" xy=(%d,%d) wh=(%dx%d) pad=(%d,%d,%d,%d) maxwh=(%d,%d) disp=%d%s",
		      i, static_cast<int>(n.parent), static_cast<int>(n.type), cls.c_str(),
		      static_cast<int>(n.layout.x), static_cast<int>(n.layout.y),
		      static_cast<int>(n.layout.width), static_cast<int>(n.layout.height),
		      static_cast<int>(n.style.padding[0]), static_cast<int>(n.style.padding[1]),
		      static_cast<int>(n.style.padding[2]), static_cast<int>(n.style.padding[3]),
		      static_cast<int>(n.style.max_width), static_cast<int>(n.style.max_height),
		      static_cast<int>(n.style.display),
		      n.type == NodeType::Text && !n.text.empty() ? n.text.c_str() : "");
	}
	for (NSNumber *key in [nodeIdToView() allKeys]) {
		UIView *view = nodeIdToView()[key];
		NSString *scroll = @"";
		if ([view isKindOfClass:[GeaNativeScrollContainer class]]) {
			GeaNativeScrollContainer *sc = (GeaNativeScrollContainer *)view;
			scroll = [NSString stringWithFormat:@" axis=%s content=%@ offset=%.1f/%.1f",
			          sc.horizontal ? "x" : "y", NSStringFromCGSize(sc.contentSize),
			          [sc geaRawOffset], [sc geaMaxOffset]];
		}
		NSLog(@"  view[%@] %@ frame=%@ hidden=%d alpha=%.2f clip=%d%@", key,
		      NSStringFromClass([view class]), NSStringFromCGRect(view.frame),
		      view.hidden ? 1 : 0, view.alpha, view.clipsToBounds ? 1 : 0, scroll);
	}
}

void syncNativeTree(UIView *parentForRoot, int rootNodeId)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	if (!parentForRoot || rootNodeId < 0 || rootNodeId >= tree.nodeCount()) return;

	NSMutableSet<NSNumber *> *unseen = [NSMutableSet setWithArray:[nodeIdToView() allKeys]];
	const CGFloat scale = canvasScaleForView(parentForRoot);
	syncRecursive(rootNodeId, parentForRoot, 0, 0, scale, unseen);
	if (std::getenv("GEA_IOS_LAYOUT_DUMP")) dumpLayout(parentForRoot, rootNodeId);

	for (NSNumber *gone in unseen) {
		UIView *view = nodeIdToView()[gone];
		[view removeFromSuperview];
		[nodeIdToView() removeObjectForKey:gone];
	}
}

void teardownNativeTree()
{
	for (UIView *view in [nodeIdToView() allValues]) {
		[view removeFromSuperview];
	}
	[nodeIdToView() removeAllObjects];
}

bool hasNativeTree()
{
	return nodeIdToView().count > 0;
}

}  // namespace gea::ios::renderer

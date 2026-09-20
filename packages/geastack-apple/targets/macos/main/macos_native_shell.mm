#import "macos_native_shell.h"

#include "macos_renderer.h"

#include "events.h"
#include "ui/document.h"
#include "ui/node.h"
#include "ui/node_model.h"
#include "ui/tree_internal.h"

#include <string>
#include <vector>

using gea::embedded::ui::NodeHandle;
using gea::embedded::ui::Tree;

namespace {

const char *nodeTag(int nodeId)
{
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return "";
	const char *t = tree.tagName(nodeId);
	return t ? t : "";
}

bool tagIs(int nodeId, const char *tag)
{
	return std::strcmp(nodeTag(nodeId), tag) == 0;
}

// First ELEMENT child (skips nothing special here — gea children are all
// nodes). Returns -1 if none.
int firstChild(int nodeId)
{
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return -1;
	return tree.node(nodeId).first_child;
}

int nextSibling(int nodeId)
{
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return -1;
	return tree.node(nodeId).next_sibling;
}

std::string attr(int nodeId, const char *name)
{
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return "";
	const char *v = tree.getAttribute(nodeId, name);
	return v ? std::string(v) : std::string();
}

// Fire Click + Press at the node carrying attribute id == elementId. Used by
// toolbar items to drive JSX onPress handlers without the item being part of
// the visual tree.
void firePressForElementId(const std::string &elementId)
{
	if (elementId.empty()) return;
	Tree &tree = Tree::instance();
	int targetId = -1;
	for (int i = 0; i < tree.nodeCount(); i++) {
		if (attr(i, "id") == elementId) { targetId = i; break; }
	}
	if (targetId < 0) return;
	using gea::framework::events::PointerEvent;
	using gea::framework::events::PointerEventType;
	auto fire = [&](PointerEventType type) {
		PointerEvent ev;
		ev.type = type;
		ev.targetId = targetId;
		tree.dispatchEvent(ev);
	};
	fire(PointerEventType::Click);
}

// The `<glass-split>` at or below `nodeId`, or -1. Bounded: the shell element is
// an app's OUTERMOST element, so it sits directly under the `#app` mount root
// (or under a wrapper or two a component added). Walking a few levels of the
// tree's head is enough and cannot wander into a deep list body.
int findGlassSplit(int nodeId, int depth = 0)
{
	if (nodeId < 0 || depth > 4) return -1;
	if (tagIs(nodeId, "glass-split")) return nodeId;
	for (int child = firstChild(nodeId); child >= 0; child = nextSibling(child)) {
		const int found = findGlassSplit(child, depth + 1);
		if (found >= 0) return found;
	}
	return -1;
}

struct PaneInfo {
	int contentNodeId;  // the gea subtree root rendered into this pane
	NSView *container;  // the split item's view (full height, behind toolbar)
	NSView *content;    // inner view inset to the safe area (below the toolbar)
	NSRect lastFrame = NSZeroRect;  // last content frame synced (resize detection)
};

struct ToolbarItemInfo {
	std::string identifier;
	std::string symbol;   // SF Symbol name
	std::string label;
	std::string actionId; // element id to press on click ("" = inert)
	bool isSearch = false;
	bool isSpace = false;       // flexible space
	bool isSidebarToggle = false;
};

}  // namespace

// Lightweight NSViewController whose view is supplied directly. Using a bare
// NSViewController subclass avoids loadView nib lookups.
@interface GeaPaneViewController : NSViewController
@end
@implementation GeaPaneViewController
- (void)loadView
{
	if (!self.view) self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
}
@end

@interface GeaSplitShell () <NSToolbarDelegate>
@property(nonatomic, strong) NSSplitViewController *splitController;
@property(nonatomic, strong) NSToolbar *toolbar;
@property(nonatomic, assign) std::vector<PaneInfo> *panes;
@property(nonatomic, assign) std::vector<ToolbarItemInfo> *toolbarItems;
@property(nonatomic, assign) uint64_t lastSerial;  // Tree::refreshSerial last synced
@end

@implementation GeaSplitShell

+ (instancetype)shellForRootNode:(int)rootNodeId window:(NSWindow *)window
{
	// The MOUNTED root is never the app's own element: `mount(App)` resolves
	// `document.getElementById('app')` and renders the component INTO it
	// (core/packages/core/runtime/primitives.ts), and `Document::ensureAppRoot`
	// is what mounts that `#app` view (engine/ui/document.cpp). So a
	// `<glass-split>` template lands one (or more) levels BELOW the node
	// `Tree::mountedRoot()` names, and matching only the root itself silently
	// declined every app that uses the shell — notes-jsx fell back to flat gea
	// layout with no toolbar and no split.
	rootNodeId = findGlassSplit(rootNodeId);
	if (rootNodeId < 0) return nil;
	GeaSplitShell *shell = [[GeaSplitShell alloc] init];
	shell.panes = new std::vector<PaneInfo>();
	shell.toolbarItems = new std::vector<ToolbarItemInfo>();

	NSSplitViewController *svc = [[NSSplitViewController alloc] init];
	svc.view.frame = [window.contentView bounds];

	// Walk glass-split children: panes + an optional <toolbar>.
	for (int child = firstChild(rootNodeId); child >= 0; child = nextSibling(child)) {
		if (tagIs(child, "toolbar")) {
			[shell parseToolbar:child];
			continue;
		}
		if (!tagIs(child, "glass-pane")) continue;
		const std::string role = attr(child, "data-pane");
		const int contentNode = firstChild(child);
		if (contentNode < 0) continue;

		GeaPaneViewController *vc = [[GeaPaneViewController alloc] init];
		NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
		container.wantsLayer = YES;
		vc.view = container;
		// Inner content view, re-framed each layout to the window's below-toolbar
		// region (contentLayoutRect) converted into THIS container's coordinate
		// space. Converting the one shared window rect per container makes every
		// pane's content top land at the exact same screen y (the toolbar
		// bottom), regardless of each split item's own frame/height — the
		// sidebar item is shorter and offset vs. the content panes, so its own
		// safeAreaInsets under-inset its first row under the toolbar. The split
		// item's glass/background still fills the full pane height because only
		// this inner view is inset.
		NSView *contentView = [[NSView alloc] initWithFrame:container.bounds];
		contentView.wantsLayer = YES;
		contentView.autoresizingMask = NSViewNotSizable;
		[container addSubview:contentView];

		NSSplitViewItem *item;
		if (role == "sidebar") {
			// Sidebar behavior gives the system-managed Liquid Glass material
			// + collapse/show animation. We must NOT paint an opaque
			// background on the container or it hides the vibrancy.
			item = [NSSplitViewItem sidebarWithViewController:vc];
			item.minimumThickness = 180;
			item.maximumThickness = 320;
			item.canCollapse = YES;
		} else if (role == "list") {
			item = [NSSplitViewItem contentListWithViewController:vc];
			item.minimumThickness = 240;
			item.maximumThickness = 460;
		} else {
			item = [NSSplitViewItem splitViewItemWithViewController:vc];
			item.minimumThickness = 320;
			container.layer.backgroundColor = [[NSColor colorWithSRGBRed:0.114 green:0.114 blue:0.122 alpha:1.0] CGColor];
		}
		[svc addSplitViewItem:item];
		shell.panes->push_back({contentNode, container, contentView});
	}

	if (shell.panes->empty()) {
		delete shell.panes;
		delete shell.toolbarItems;
		return nil;
	}

	shell.splitController = svc;
	window.contentViewController = svc;

	if (!shell.toolbarItems->empty()) {
		NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"gea.toolbar"];
		tb.delegate = shell;
		tb.displayMode = NSToolbarDisplayModeIconOnly;
		tb.allowsUserCustomization = NO;
		shell.toolbar = tb;
		window.toolbar = tb;
		if (@available(macOS 11.0, *)) window.toolbarStyle = NSWindowToolbarStyleUnified;
	}

	return shell;
}

- (void)parseToolbar:(int)toolbarNode
{
	for (int item = firstChild(toolbarNode); item >= 0; item = nextSibling(item)) {
		ToolbarItemInfo info;
		if (tagIs(item, "toolbar-search")) {
			info.isSearch = true;
			info.identifier = "gea.search";
		} else if (tagIs(item, "toolbar-space")) {
			info.isSpace = true;
			info.identifier = NSToolbarFlexibleSpaceItemIdentifier.UTF8String;
		} else if (tagIs(item, "toolbar-item")) {
			info.symbol = attr(item, "data-symbol");
			info.label = attr(item, "data-label");
			info.actionId = attr(item, "data-action");
			info.isSidebarToggle = attr(item, "data-role") == "sidebar-toggle";
			info.identifier = "gea.item." + std::to_string(_toolbarItems->size());
		} else {
			continue;
		}
		_toolbarItems->push_back(info);
	}
}

- (void)layoutAndSync
{
	if (!_panes || _panes->empty()) return;
	Tree &tree = Tree::instance();
	const bool dbg = getenv("GEA_DEBUG_SHELL") != nullptr;
	const std::size_t count = _panes->size();

	NSWindow *window = nil;
	for (const PaneInfo &pane : *_panes) {
		if (pane.container.window) { window = pane.container.window; break; }
	}
	NSView *windowContent = window.contentView;
	const NSRect belowToolbar = window ? window.contentLayoutRect : NSZeroRect;

	// Cheap pass: compute each pane's content frame (a rect convert + clip) and
	// detect whether anything moved. This is the only work done every frame.
	std::vector<NSRect> frames(count);
	bool anyFrameChanged = false;
	for (std::size_t i = 0; i < count; i++) {
		const PaneInfo &pane = (*_panes)[i];
		NSView *container = pane.container;
		// Convert the window's below-toolbar rect into this container's space and
		// clip to the container, so the content view's TOP edge lands exactly at
		// the toolbar bottom in screen space — identical y across all panes.
		NSRect inContainer = windowContent
		    ? [container convertRect:belowToolbar fromView:windowContent]
		    : container.bounds;
		NSRect contentFrame = NSIntersectionRect(inContainer, container.bounds);
		if (NSIsEmptyRect(contentFrame)) contentFrame = container.bounds;
		frames[i] = contentFrame;
		if (!NSEqualRects(contentFrame, pane.lastFrame)) anyFrameChanged = true;
	}

	// Skip the expensive layout + full view diff unless the reactive tree changed
	// (Tree::refreshSerial bumps on mount/refresh) or a pane resized. This is what
	// keeps an idle Notes window off the CPU instead of re-syncing 60×/sec.
	const uint64_t serial = tree.refreshSerial();
	if (serial == _lastSerial && !anyFrameChanged) return;

	NSMutableArray *paneViews = [NSMutableArray arrayWithCapacity:count];
	std::vector<int> rootIds;
	rootIds.reserve(count);
	for (std::size_t i = 0; i < count; i++) {
		PaneInfo &pane = (*_panes)[i];
		const NSRect contentFrame = frames[i];
		pane.content.frame = contentFrame;
		pane.lastFrame = contentFrame;
		const int w = static_cast<int>(contentFrame.size.width);
		const int h = static_cast<int>(contentFrame.size.height);
		if (dbg) {
			fprintf(stderr, "[shell]   pane node=%d container=%.0fx%.0f -> content=%dx%d (serial=%llu)\n",
			        pane.contentNodeId, pane.container.bounds.size.width, pane.container.bounds.size.height,
			        w, h, (unsigned long long)serial);
		}
		if (w <= 0 || h <= 0) continue;
		if (pane.contentNodeId < 0 || pane.contentNodeId >= tree.nodeCount()) continue;
		NodeHandle(pane.contentNodeId).style().width(w);
		NodeHandle(pane.contentNodeId).style().height(h);
		tree.computeLayout(pane.contentNodeId, w, h);
		[paneViews addObject:pane.content];
		rootIds.push_back(pane.contentNodeId);
	}
	_lastSerial = serial;
	if (paneViews.count == 0) return;
	gea::macos::MacosRenderer::instance().syncPanes(paneViews, rootIds.data());
}

#pragma mark NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarItemIdentifiers
{
	NSMutableArray *ids = [NSMutableArray array];
	for (const ToolbarItemInfo &info : *_toolbarItems) {
		[ids addObject:[NSString stringWithUTF8String:info.identifier.c_str()]];
	}
	return ids;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarItemIdentifiers];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	return [self toolbarItemIdentifiers];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
	const std::string ident = itemIdentifier.UTF8String;
	for (const ToolbarItemInfo &info : *_toolbarItems) {
		if (info.identifier != ident) continue;
		if (info.isSpace) return nil;  // standard identifier, AppKit provides it
		if (info.isSearch) {
			NSSearchToolbarItem *search = [[NSSearchToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
			search.resignsFirstResponderWithCancel = YES;
			return search;
		}
		NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
		NSString *label = [NSString stringWithUTF8String:info.label.c_str()];
		toolbarItem.label = label;
		toolbarItem.toolTip = label;
		NSImage *image = nil;
		if (!info.symbol.empty()) {
			NSString *sym = [NSString stringWithUTF8String:info.symbol.c_str()];
			image = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:label];
		}
		toolbarItem.image = image;
		toolbarItem.bordered = YES;
		if (info.isSidebarToggle) {
			toolbarItem.target = self.splitController;
			toolbarItem.action = @selector(toggleSidebar:);
		} else {
			toolbarItem.target = self;
			toolbarItem.action = @selector(toolbarItemClicked:);
			// Stash the action element id on the item via its identifier map;
			// we resolve it back in the action by scanning _toolbarItems.
		}
		return toolbarItem;
	}
	return nil;
}

- (void)toolbarItemClicked:(NSToolbarItem *)sender
{
	// Drop focus from any in-flight text field or textarea before firing the
	// action. Without this the reactive `value`-update guard in applyTextProps /
	// applyTextAreaProps sees firstResponder != nil and skips the write, so the
	// editor title/body never clears when the user clicks e.g. "New Note" while
	// the body textarea is still focused. (Same pattern as the gesture
	// recognizer's NSGestureRecognizerStateBegan handler.)
	NSWindow *window = [NSApp keyWindow];
	if (window && window.firstResponder != window) {
		[window makeFirstResponder:nil];
	}
	const std::string ident = sender.itemIdentifier.UTF8String;
	for (const ToolbarItemInfo &info : *_toolbarItems) {
		if (info.identifier == ident) {
			firePressForElementId(info.actionId);
			return;
		}
	}
}

@end

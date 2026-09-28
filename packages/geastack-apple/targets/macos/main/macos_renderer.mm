#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
// CIGaussianBlur for `filter: blur()`. QuartzCore re-exports CoreImage, but the
// umbrella header only pulls it in when modules are off — import it directly.
#import <CoreImage/CoreImage.h>

#include "macos_renderer.h"
#include "canvas_view.h"
#include "color_convert.h"
#include "font_registry.h"
#include "image_bridge.h"
#include "press_bridge.h"

#include "ui/tree_internal.h"
#include "ui/node_model.h"

#include "events.h"

#import <objc/runtime.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <cstring>
#include <cstdlib>
#include <vector>

// NSTextField defaults to consuming mouse events even when bezeled / editable /
// selectable are all NO. That blocks the NSClickGestureRecognizer on the
// containing View (e.g. an app-launcher tile) from firing when the user
// clicks on the label, because the label sits on top and hit-tests first.
// Override hitTest to make the label transparent — mouse events pass through
// to the containing View where the recognizer can pick them up. We only ever
// render non-editable, non-selectable labels via makeTextField, so this is
// safe; if/when input fields land they'll need their own NSTextField
// subclass that accepts mouse.
// NSTextFieldCell reserves a couple of pixels on each edge for the focus
// ring even when bezeled/bordered are NO — so a field sized for the
// measured text width clips a few pixels off the right glyph ("JUMP" →
// "JUM"). This subclass overrides drawingRectForBounds: to use the field's
// full bounds, with no implicit padding, so the text fits the same space
// our host measurement reported.
@interface GeaTextCell : NSTextFieldCell
@end
@implementation GeaTextCell
- (NSRect)drawingRectForBounds:(NSRect)bounds { return bounds; }
- (NSRect)titleRectForBounds:(NSRect)bounds { return bounds; }
@end

@interface GeaLabelTextField : NSTextField
@end
@implementation GeaLabelTextField
+ (Class)cellClass { return [GeaTextCell class]; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

// Editable text field used to materialize `<input>` JSX elements. Holds the
// owning node id and forwards `controlTextDidChange:` to the framework as an
// `input` PointerEvent; the framework's per-node listener registry then routes
// it to whatever `onInput={...}` handler the app installed. We also override
// the field-editor's keyDown: path via NSTextViewDelegate's
// `textView:doCommandBySelector:` so Enter / arrows / etc. dispatch as
// `keydown` events with the corresponding `keyCode` value JS apps expect
// (matching the browser keyCode table for the few keys the framework cares
// about — Enter, Backspace, arrows, Escape, Tab).
@interface GeaInputField : NSTextField <NSTextFieldDelegate>
@property(nonatomic, assign) int nodeId;
@end

@implementation GeaInputField

- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		_nodeId = -1;
		self.delegate = self;
	}
	return self;
}

static int geaKeyCodeForCommand(SEL sel)
{
	// Map AppKit's responder selectors (the field editor calls these on its
	// delegate when the user presses control keys) to the keyCode values JS
	// apps read from `event.keyCode`. Only the keys real apps actually
	// branch on; everything else falls through with 0 (no keydown fired).
	if (sel == @selector(insertNewline:)) return 13;          // Enter
	if (sel == @selector(insertLineBreak:)) return 13;        // Shift+Enter
	if (sel == @selector(insertTab:)) return 9;               // Tab
	if (sel == @selector(insertBacktab:)) return 9;
	if (sel == @selector(cancelOperation:)) return 27;        // Esc
	if (sel == @selector(deleteBackward:)) return 8;          // Backspace
	if (sel == @selector(deleteForward:)) return 46;          // Delete
	if (sel == @selector(moveLeft:)) return 37;
	if (sel == @selector(moveUp:)) return 38;
	if (sel == @selector(moveRight:)) return 39;
	if (sel == @selector(moveDown:)) return 40;
	return 0;
}

- (void)dispatchEventOfType:(gea::framework::events::PointerEventType)type withKeyCode:(int)keyCode
{
	using gea::framework::events::PointerEvent;
	if (_nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	PointerEvent event;
	event.type = type;
	event.targetId = _nodeId;
	event.keyCode = keyCode;
	tree.dispatchEvent(event);
}

- (void)controlTextDidChange:(NSNotification *)note
{
	(void)note;
	if (_nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	const std::string newValue = std::string([self.stringValue UTF8String] ?: "");
	// Mirror the current text into the node's `value` attribute. The
	// framework's DOM-shim reads `event.currentTarget.value` by falling
	// through to `getAttribute("value")`, so the user's onInput handler sees
	// the latest text without us needing a dedicated event-payload slot.
	tree.setAttribute(_nodeId, "value", newValue.c_str());
	[self dispatchEventOfType:gea::framework::events::PointerEventType::Input withKeyCode:0];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
	(void)control;
	(void)textView;
	const int keyCode = geaKeyCodeForCommand(commandSelector);
	if (keyCode != 0) {
		[self dispatchEventOfType:gea::framework::events::PointerEventType::KeyDown withKeyCode:keyCode];
		// Returning NO lets the field editor still process the command
		// (Enter still commits, arrows still move the caret). Apps that
		// want to override should call preventDefault on the event — not
		// yet wired through.
	}
	return NO;
}

@end

// Multi-line text editor. Materialized by `<textarea>` in JSX. The framework
// only knows about `<input>` (single-line NSTextField); textarea adds proper
// NSTextView semantics — Enter inserts a newline, soft-wrap, scrolling — for
// notes-style apps. Lives inside its own NSScrollView so long bodies scroll
// natively. Mirrors GeaInputField's contract: holds the owning node id,
// listens for text changes and reflects them to the node's `value` attribute
// so user code reading `event.currentTarget.value` (or observing the store
// bound to it) sees the latest text.
@interface GeaTextAreaView : NSTextView <NSTextViewDelegate>
@property(nonatomic, assign) int nodeId;
@property(nonatomic, assign) BOOL suppressChangeNotification;
@end

@implementation GeaTextAreaView
- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(NSTextContainer *)container
{
	if ((self = [super initWithFrame:frameRect textContainer:container])) {
		_nodeId = -1;
		_suppressChangeNotification = NO;
		self.delegate = self;
		self.allowsUndo = YES;
		self.richText = NO;
		self.importsGraphics = NO;
		self.usesFontPanel = NO;
		self.usesRuler = NO;
		self.smartInsertDeleteEnabled = YES;
		self.automaticQuoteSubstitutionEnabled = NO;
		self.automaticDashSubstitutionEnabled = NO;
		self.automaticTextReplacementEnabled = NO;
		self.automaticSpellingCorrectionEnabled = NO;
	}
	return self;
}

- (void)textDidChange:(NSNotification *)note
{
	(void)note;
	if (_nodeId < 0 || _suppressChangeNotification) return;
	using gea::framework::events::PointerEvent;
	using gea::framework::events::PointerEventType;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	const std::string newValue = std::string([self.string UTF8String] ?: "");
	tree.setAttribute(_nodeId, "value", newValue.c_str());
	PointerEvent event;
	event.type = PointerEventType::Input;
	event.targetId = _nodeId;
	event.keyCode = 0;
	tree.dispatchEvent(event);
}
@end

// Root-level click handler. Installed once on the contentView during
// MacosRenderer::sync. On click, asks the recognizer for the location,
// hit-tests against the root, then walks up via nodeIdForView to find the
// deepest view that's tagged with a node id, and dispatches click+press
// to that nodeId. Matches the framework's event-delegation model — listeners
// bound on document.body fire and check event.target to figure out which
// node was clicked.
@interface GeaRootClickBridge : NSObject <NSGestureRecognizerDelegate>
@property(nonatomic, weak) NSView *rootView;
@property(nonatomic, assign) int pressedNodeId;  // -1 when no press in flight
- (void)fire:(NSGestureRecognizer *)gr;
@end

namespace gea::macos {
int nodeIdForView(NSView *view)
{
	while (view) {
		NSNumber *n = objc_getAssociatedObject(view, "gea.node_id");
		if (n) return n.intValue;
		view = view.superview;
	}
	return -1;
}
}  // namespace gea::macos

@implementation GeaRootClickBridge

- (instancetype)init
{
	if ((self = [super init])) {
		_pressedNodeId = -1;
	}
	return self;
}

- (void)fire:(NSGestureRecognizer *)gr
{
	using gea::framework::events::PointerEvent;
	using gea::framework::events::PointerEventType;
	NSView *root = self.rootView;
	if (!root) return;

	auto fireEvent = [&](int nodeId, PointerEventType type) {
		if (nodeId < 0) return;
		auto &tree = gea::embedded::ui::Tree::instance();
		if (nodeId >= tree.nodeCount()) return;
		PointerEvent ev;
		ev.type = type;
		ev.targetId = nodeId;
		tree.dispatchEvent(ev);
	};

	switch (gr.state) {
	case NSGestureRecognizerStateBegan: {
		// Clicking a non-editable target (a note/folder row, a button) ends any
		// in-flight text editing first — exactly like clicking away in Notes.
		// This commits the edit AND drops first-responder, so next frame the
		// editor's value guard no longer skips, letting the title/body refresh
		// to the newly selected note. (Clicks on editable fields never reach
		// this recognizer — the delegate declines them.)
		if (root.window.firstResponder != root.window) {
			[root.window makeFirstResponder:nil];
		}
		// Mouse-down: hit-test now, remember the node so the up phase
		// dispatches to the same target even if the cursor drifts.
		const NSPoint pInRoot = [gr locationInView:root];
		const NSPoint pInSuper = [root convertPoint:pInRoot toView:root.superview];
		NSView *hit = [root.superview hitTest:pInSuper];
		self.pressedNodeId = gea::macos::nodeIdForView(hit);
		fireEvent(self.pressedNodeId, PointerEventType::TouchStart);
		break;
	}
	case NSGestureRecognizerStateEnded:
	case NSGestureRecognizerStateCancelled:
	case NSGestureRecognizerStateFailed: {
		const int nodeId = self.pressedNodeId;
		self.pressedNodeId = -1;
		fireEvent(nodeId, PointerEventType::TouchEnd);
		if (gr.state == NSGestureRecognizerStateEnded) {
			fireEvent(nodeId, PointerEventType::Click);
		}
		break;
	}
	default:
		break;
	}
}

// Don't let the root press-recognizer swallow clicks that land on an editable
// text control (the note title <input> / body <textarea>). If we recognized
// those, the field never becomes first responder and the user can't focus or
// type. Returning NO lets the event flow through AppKit's normal hit-test /
// responder path so the field edits natively. Non-editable label rows (sidebar
// folders, note rows) still recognize → gea Press fires.
- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer
    shouldAttemptToRecognizeWithEvent:(NSEvent *)event
{
	(void)gestureRecognizer;
	NSView *root = self.rootView;
	if (!root || !root.window) return YES;
	NSView *content = root.window.contentView;
	const NSPoint p = [content convertPoint:event.locationInWindow fromView:nil];
	NSView *hit = [content hitTest:p];
	for (NSView *v = hit; v != nil; v = v.superview) {
		if ([v isKindOfClass:[NSTextView class]]) return NO;
		if ([v isKindOfClass:[NSTextField class]] && ((NSTextField *)v).isEditable) return NO;
		// Canvas views dispatch their own coordinate-carrying touch events
		// (mouseDown/Dragged/Up in GeaCanvasView) — recognizing here too would
		// double-fire the press, with this path's events carrying no coords.
		if ([v isKindOfClass:[GeaCanvasView class]]) return NO;
		// A scroll container's scroller tracks its own knob drag; recognizing
		// the press here took the whole drag and the knob never moved.
		if ([v isKindOfClass:[NSScroller class]]) return NO;
	}
	return YES;
}
@end

// Flipped clip view so scroll content is TOP-aligned: the first row sits at the
// top of the viewport, and content shorter than the viewport leaves its empty
// space at the BOTTOM (natural for a top-down list). With the default
// (unflipped) clip view, short content bottom-aligns, leaving a gap above the
// first row. The document view itself stays unflipped, so syncRecursive's
// y-flip against scroll_content_height is unchanged.
@interface GeaFlippedClipView : NSClipView
@end
@implementation GeaFlippedClipView
- (BOOL)isFlipped { return YES; }
@end

// NSSlider materialized by `<input type="range">`. Continuous; on each value
// change it writes its integer value into the node's `value` attribute and
// dispatches an `input` PointerEvent, so the app's onInput handler reads the new
// value off event.currentTarget.value (same convention as GeaInputField).
@interface GeaSlider : NSSlider
@property(nonatomic, assign) int nodeId;
@property(nonatomic, assign) BOOL geaDragging;
@end

@implementation GeaSlider
- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		_nodeId = -1;
		_geaDragging = NO;
	}
	return self;
}
- (void)mouseDown:(NSEvent *)event
{
	// Guard the tracking loop so applySliderProps doesn't fight the user's drag
	// by writing back a (possibly lagging) bound value mid-gesture.
	_geaDragging = YES;
	[super mouseDown:event];
	_geaDragging = NO;
}
- (void)geaChanged:(id)sender
{
	(void)sender;
	if (_nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	const int v = (int)(self.doubleValue + 0.5);
	tree.setAttribute(_nodeId, "value", std::to_string(v).c_str());
	gea::framework::events::PointerEvent event;
	event.type = gea::framework::events::PointerEventType::Input;
	event.targetId = _nodeId;
	tree.dispatchEvent(event);
}
@end

// NSSwitch materialized by `<input type="checkbox">`. On toggle it writes
// "true"/"false" into the node's `checked` attribute and dispatches an `input`
// PointerEvent, so the app's onInput handler flips the bound store field.
@interface GeaSwitch : NSSwitch
@property(nonatomic, assign) int nodeId;
@end

@implementation GeaSwitch
- (instancetype)initWithFrame:(NSRect)frameRect
{
	if ((self = [super initWithFrame:frameRect])) {
		_nodeId = -1;
	}
	return self;
}
- (void)geaChanged:(id)sender
{
	(void)sender;
	if (_nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	const bool on = self.state == NSControlStateValueOn;
	tree.setAttribute(_nodeId, "checked", on ? "true" : "false");
	gea::framework::events::PointerEvent event;
	event.type = gea::framework::events::PointerEventType::Input;
	event.targetId = _nodeId;
	tree.dispatchEvent(event);
}
@end

namespace gea::macos {

namespace {

// nodeId → NSView. Lifetimes are owned by the dictionary (strong refs); when
// teardown removes the entry the view is released and removeFromSuperview is
// idempotent so we don't leak stale subview pointers.
NSMutableDictionary<NSNumber *, NSView *> *nodeIdToView()
{
	static NSMutableDictionary<NSNumber *, NSView *> *map = [NSMutableDictionary new];
	return map;
}

bool isScrollView(NSView *view)
{
	return [view isKindOfClass:[NSScrollView class]];
}

NSView *makeTextField()
{
	GeaLabelTextField *tf = [[GeaLabelTextField alloc] initWithFrame:NSZeroRect];
	tf.bezeled = NO;
	tf.bordered = NO;
	tf.drawsBackground = NO;
	tf.editable = NO;
	tf.selectable = NO;
	tf.usesSingleLineMode = NO;
	// Word-wrap so multi-word labels break at spaces — applyTextProps
	// builds the actual attributed string with the same setting plus
	// kerning=0 + fixed line height, so AppKit's rendered geometry
	// matches what the framework's layout engine measured.
	tf.lineBreakMode = NSLineBreakByWordWrapping;
	tf.cell.wraps = YES;
	tf.cell.truncatesLastVisibleLine = NO;
	[tf setWantsLayer:YES];
	return tf;
}

NSView *makeCanvasView()
{
	GeaCanvasView *cv = [[GeaCanvasView alloc] initWithFrame:NSZeroRect];
	[cv setWantsLayer:YES];
	return cv;
}

NSView *makeScrollView()
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	sv.hasVerticalScroller = YES;
	sv.hasHorizontalScroller = NO;
	sv.autohidesScrollers = YES;
	sv.borderType = NSNoBorder;
	sv.drawsBackground = NO;
	sv.verticalScrollElasticity = NSScrollElasticityAllowed;
	sv.horizontalScrollElasticity = NSScrollElasticityNone;
	sv.usesPredominantAxisScrolling = YES;
	// The clip view (NSClipView) draws controlBackgroundColor (gray) by default,
	// which shows through wherever the scrolled content is transparent. Turn it
	// off so the app's own background shows behind the scroll content.
	GeaFlippedClipView *clip = [[GeaFlippedClipView alloc] initWithFrame:NSZeroRect];
	clip.drawsBackground = NO;
	sv.contentView = clip;
	NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
	[content setWantsLayer:YES];
	sv.documentView = content;
	return sv;
}

NSView *makeImageView()
{
	NSImageView *iv = [[NSImageView alloc] initWithFrame:NSZeroRect];
	iv.imageScaling = NSImageScaleAxesIndependently;
	iv.editable = NO;
	[iv setWantsLayer:YES];
	return iv;
}

NSView *makeSlider()
{
	GeaSlider *sl = [[GeaSlider alloc] initWithFrame:NSZeroRect];
	sl.sliderType = NSSliderTypeLinear;
	sl.minValue = 0;
	sl.maxValue = 100;
	sl.continuous = YES;
	sl.target = sl;
	sl.action = @selector(geaChanged:);
	return sl;
}

NSView *makeSwitch()
{
	GeaSwitch *sw = [[GeaSwitch alloc] initWithFrame:NSZeroRect];
	sw.target = sw;
	sw.action = @selector(geaChanged:);
	return sw;
}

NSView *makeButton()
{
	NSButton *btn = [[NSButton alloc] initWithFrame:NSZeroRect];
	btn.buttonType = NSButtonTypeMomentaryLight;
	btn.bezelStyle = NSBezelStyleRounded;
	[btn setWantsLayer:YES];
	PressBridge *bridge = [[PressBridge alloc] init];
	bridge.nodeId = -1;  // set during applyButtonProps
	objc_setAssociatedObject(btn, "gea.press_bridge", bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	btn.target = bridge;
	btn.action = @selector(fire:);
	return btn;
}

NSView *makeInputField()
{
	GeaInputField *tf = [[GeaInputField alloc] initWithFrame:NSZeroRect];
	tf.bezeled = NO;
	tf.bordered = NO;
	tf.drawsBackground = NO;
	tf.editable = YES;
	tf.selectable = YES;
	tf.usesSingleLineMode = YES;
	tf.focusRingType = NSFocusRingTypeNone;
	[tf setWantsLayer:YES];
	return tf;
}

NSVisualEffectMaterial vibrancyMaterialFromString(const char *name)
{
	if (!name || !name[0]) return NSVisualEffectMaterialSidebar;
	if (std::strcmp(name, "sidebar") == 0) return NSVisualEffectMaterialSidebar;
	if (std::strcmp(name, "header") == 0) return NSVisualEffectMaterialHeaderView;
	if (std::strcmp(name, "content") == 0) return NSVisualEffectMaterialContentBackground;
	if (std::strcmp(name, "under-window") == 0) return NSVisualEffectMaterialUnderWindowBackground;
	if (std::strcmp(name, "under-page") == 0) return NSVisualEffectMaterialUnderPageBackground;
	if (std::strcmp(name, "window-background") == 0) return NSVisualEffectMaterialWindowBackground;
	if (std::strcmp(name, "titlebar") == 0) return NSVisualEffectMaterialTitlebar;
	if (std::strcmp(name, "menu") == 0) return NSVisualEffectMaterialMenu;
	if (std::strcmp(name, "popover") == 0) return NSVisualEffectMaterialPopover;
	if (std::strcmp(name, "hud") == 0) return NSVisualEffectMaterialHUDWindow;
	if (std::strcmp(name, "selection") == 0) return NSVisualEffectMaterialSelection;
	if (std::strcmp(name, "tooltip") == 0) return NSVisualEffectMaterialToolTip;
	if (std::strcmp(name, "fullscreen-ui") == 0) return NSVisualEffectMaterialFullScreenUI;
	return NSVisualEffectMaterialSidebar;
}

NSVisualEffectBlendingMode vibrancyBlendingFromString(const char *name)
{
	if (!name || !name[0]) return NSVisualEffectBlendingModeBehindWindow;
	if (std::strcmp(name, "within") == 0) return NSVisualEffectBlendingModeWithinWindow;
	if (std::strcmp(name, "within-window") == 0) return NSVisualEffectBlendingModeWithinWindow;
	if (std::strcmp(name, "behind") == 0) return NSVisualEffectBlendingModeBehindWindow;
	if (std::strcmp(name, "behind-window") == 0) return NSVisualEffectBlendingModeBehindWindow;
	return NSVisualEffectBlendingModeBehindWindow;
}

NSView *makeVibrancyView()
{
	NSVisualEffectView *ve = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
	ve.material = NSVisualEffectMaterialSidebar;
	ve.blendingMode = NSVisualEffectBlendingModeBehindWindow;
	ve.state = NSVisualEffectStateFollowsWindowActiveState;
	ve.wantsLayer = YES;
	return ve;
}

// `<symbol data-symbol="folder">` → NSImageView showing the named SF Symbol.
// SF Symbols are template images; contentTintColor (from CSS color via
// data-color, or labelColor) colors them. Tagged so applyTypeSpecificProps
// routes it to applySymbolProps rather than the bitmap-image path.
NSView *makeSymbolView()
{
	NSImageView *iv = [[NSImageView alloc] initWithFrame:NSZeroRect];
	iv.imageScaling = NSImageScaleProportionallyUpOrDown;
	iv.imageAlignment = NSImageAlignCenter;
	iv.editable = NO;
	[iv setWantsLayer:YES];
	objc_setAssociatedObject(iv, "gea.is_symbol", @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return iv;
}

// `<textarea>` materializes as an NSScrollView containing a GeaTextAreaView.
// applyViewStyle frames the scroll view; applyTextAreaProps drives the inner
// text view's string / font / color and pushes user edits back into the
// node's `value` attribute. The text view's textContainer is set up to track
// the scroll view's content width, so wrapping behaves like a typical
// document editor.
NSView *makeTextArea()
{
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	sv.hasVerticalScroller = YES;
	sv.hasHorizontalScroller = NO;
	sv.autohidesScrollers = YES;
	sv.borderType = NSNoBorder;
	sv.drawsBackground = NO;
	sv.verticalScrollElasticity = NSScrollElasticityAllowed;
	sv.horizontalScrollElasticity = NSScrollElasticityNone;
	[sv setWantsLayer:YES];

	const NSSize cs = sv.contentSize;
	NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(cs.width, CGFLOAT_MAX)];
	tc.widthTracksTextView = YES;
	NSLayoutManager *lm = [[NSLayoutManager alloc] init];
	[lm addTextContainer:tc];
	NSTextStorage *ts = [[NSTextStorage alloc] init];
	[ts addLayoutManager:lm];

	GeaTextAreaView *tv = [[GeaTextAreaView alloc] initWithFrame:NSMakeRect(0, 0, cs.width, cs.height)
	                                                textContainer:tc];
	tv.minSize = NSMakeSize(0, cs.height);
	tv.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	tv.verticallyResizable = YES;
	tv.horizontallyResizable = NO;
	tv.autoresizingMask = NSViewWidthSizable;
	tv.drawsBackground = NO;
	tv.textContainerInset = NSMakeSize(0, 0);

	sv.documentView = tv;
	objc_setAssociatedObject(sv, "gea.text_view", tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return sv;
}

// `<input>` JSX elements go through createElement with no special tag handling
// at the framework level — they fall through to `createView()`, so node.type
// is View but node.tag_name == "input". The renderer-side dispatch teaches
// makeViewForType about that distinction so an editable NSTextField gets
// materialized instead of an empty NSView. Calls to applyInputProps later
// pick up placeholder / value / font / color from the node.
NSView *makeViewForType(gea::embedded::ui::NodeType type, const char *tagName,
                        const gea::embedded::ui::ComputedStyle &style, const char *inputType)
{
	using gea::embedded::ui::NodeType;
	if (type == NodeType::View && tagName && std::strcmp(tagName, "input") == 0) {
		if (inputType && std::strcmp(inputType, "range") == 0) return makeSlider();
		if (inputType && std::strcmp(inputType, "checkbox") == 0) return makeSwitch();
		return makeInputField();
	}
	if (type == NodeType::View && tagName && std::strcmp(tagName, "textarea") == 0) {
		return makeTextArea();
	}
	if (type == NodeType::View && tagName && std::strcmp(tagName, "vibrancy") == 0) {
		return makeVibrancyView();
	}
	if (type == NodeType::View && tagName && std::strcmp(tagName, "symbol") == 0) {
		return makeSymbolView();
	}
	switch (type) {
	case NodeType::Text:
		return makeTextField();
	case NodeType::Button:
		return makeButton();
	case NodeType::Image:
		return makeImageView();
	case NodeType::Canvas:
		return makeCanvasView();
	case NodeType::VirtualList:
		return makeScrollView();
	case NodeType::View:
	default: {
		// overflow == 2 is `scroll` in the framework's style enum. Materialize
		// such a View as an NSScrollView so AppKit handles wheel/trackpad
		// scrolling and clipping natively, matching what the framework's
		// pixel-renderer would do on hardware.
		if (style.overflow == 2) return makeScrollView();
		NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
		[view setWantsLayer:YES];
		return view;
	}
	}
}

// ---------------------------------------------------------------------------
// CSS border-radius (incl. percentages), filter: blur() and box-shadow.
//
// This target does not rasterise with the engine — it maps the node tree onto
// real AppKit views — so anything the engine expresses only inside its software
// rasteriser is lost unless it is re-expressed with CALayer primitives here.
// Three properties were in exactly that state: parsed, stored, then dropped.
//
//  * `border-radius: <percent>` lives in ComputedStyle::border_radius_percent[]
//    (ui/node_model.h), a SEPARATE array from the pixel radii, and resolves to
//    an ELLIPTICAL rx/ry pair (w*p, h*p). CALayer.cornerRadius is a single
//    scalar: it cannot express rx != ry, nor four different corners. Those
//    cases need a real path, so they get a CAShapeLayer.
//  * `filter: blur(n)` maps to CALayer.filters — NOT backgroundFilters: CSS
//    `filter` blurs the element and its subtree, `backgroundFilters` blurs what
//    is painted behind it (that is CSS `backdrop-filter`).
//  * `box-shadow`: the engine's parser only ever stores an INSET shadow — see
//    style.cpp parseInsetBoxShadow, which `continue`s past every non-inset
//    layer and zeroes box_shadow_alpha. So an inset shadow is the only shadow
//    that reaches a node, and CALayer's shadow* properties (which cast
//    outwards) cannot draw it directly; it is drawn from a shadowPath ring.
//
// The radius resolution mirrors the engine's own rule — ui/view.cpp
// resolvedBorderRadii8 and ui/tree_render.cpp resolveNodeCircularRadii:
// percent → (w*p, h*p), pixel → (r, r), then the CSS 9.4 overlap scale-down so
// two radii on one side never sum past that side's length. It is restated here
// rather than shared because both engine helpers are file-local to raster
// translation units this target never links against.
// ---------------------------------------------------------------------------

struct ResolvedRadii {
	CGFloat rx[4];  // CSS corner order: top-left, top-right, bottom-right, bottom-left
	CGFloat ry[4];
	bool uniform;  // all four corners circular AND equal → layer.cornerRadius suffices
};

ResolvedRadii resolveRadii(const gea::embedded::ui::Node &node, CGFloat w, CGFloat h)
{
	ResolvedRadii out{};
	const double width = std::max(0.0, static_cast<double>(w));
	const double height = std::max(0.0, static_cast<double>(h));
	double rx[4]{};
	double ry[4]{};
	for (int i = 0; i < 4; ++i) {
		if (node.style.border_radius_percent[i] != gea::embedded::ui::kUnset) {
			const double p = static_cast<double>(node.style.border_radius_percent[i]) / 1000.0;
			rx[i] = std::max(0.0, width * p);
			ry[i] = std::max(0.0, height * p);
		} else {
			const double r = std::max(0, static_cast<int>(node.style.border_radius[i]));
			rx[i] = r;
			ry[i] = r;
		}
	}

	double scale = 1.0;
	const auto constrain = [&](double limit, double sum) {
		if (limit > 0.0 && sum > limit) scale = std::min(scale, limit / sum);
	};
	constrain(width, rx[0] + rx[1]);
	constrain(width, rx[3] + rx[2]);
	constrain(height, ry[0] + ry[3]);
	constrain(height, ry[1] + ry[2]);

	out.uniform = true;
	for (int i = 0; i < 4; ++i) {
		out.rx[i] = static_cast<CGFloat>(rx[i] * scale);
		out.ry[i] = static_cast<CGFloat>(ry[i] * scale);
		if (std::fabs(out.rx[i] - out.ry[i]) > 0.5) out.uniform = false;
		if (std::fabs(out.rx[i] - out.rx[0]) > 0.5) out.uniform = false;
		if (std::fabs(out.ry[i] - out.ry[0]) > 0.5) out.uniform = false;
	}
	return out;
}

// Rounded rect with per-corner ELLIPTICAL radii. CGPathAddArcToPoint only draws
// circular arcs, so each corner is the standard cubic approximation of a
// quarter ellipse (kappa = 4/3 * (sqrt(2) - 1)).
//
// `flipped` is the owning view's isFlipped: an unflipped NSView's layer has y
// growing upward, so CSS "top" is max-y; a flipped one (NSClipView and friends)
// has y growing downward and the top/bottom corner pairs swap.
CGPathRef createRoundedRectPath(CGRect rect, const CGFloat rxIn[4], const CGFloat ryIn[4], bool flipped)
{
	static const CGFloat kKappa = 0.5522847498307936;
	// Index by visual position in the layer's own coordinate space.
	const int upperLeft = flipped ? 3 : 0;
	const int upperRight = flipped ? 2 : 1;
	const int lowerRight = flipped ? 1 : 2;
	const int lowerLeft = flipped ? 0 : 3;
	const CGFloat x = CGRectGetMinX(rect);
	const CGFloat y = CGRectGetMinY(rect);
	const CGFloat w = CGRectGetWidth(rect);
	const CGFloat h = CGRectGetHeight(rect);
	const CGFloat ulx = rxIn[upperLeft], uly = ryIn[upperLeft];
	const CGFloat urx = rxIn[upperRight], ury = ryIn[upperRight];
	const CGFloat lrx = rxIn[lowerRight], lry = ryIn[lowerRight];
	const CGFloat llx = rxIn[lowerLeft], lly = ryIn[lowerLeft];

	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, x + llx, y);
	CGPathAddLineToPoint(path, NULL, x + w - lrx, y);
	CGPathAddCurveToPoint(path, NULL, x + w - lrx + kKappa * lrx, y, x + w, y + lry - kKappa * lry,
	                      x + w, y + lry);
	CGPathAddLineToPoint(path, NULL, x + w, y + h - ury);
	CGPathAddCurveToPoint(path, NULL, x + w, y + h - ury + kKappa * ury,
	                      x + w - urx + kKappa * urx, y + h, x + w - urx, y + h);
	CGPathAddLineToPoint(path, NULL, x + ulx, y + h);
	CGPathAddCurveToPoint(path, NULL, x + ulx - kKappa * ulx, y + h, x, y + h - uly + kKappa * uly,
	                      x, y + h - uly);
	CGPathAddLineToPoint(path, NULL, x, y + lly);
	CGPathAddCurveToPoint(path, NULL, x, y + lly - kKappa * lly, x + llx - kKappa * llx, y,
	                      x + llx, y);
	CGPathCloseSubpath(path);
	return path;
}

// Layers this file attaches to a view are cached on it (keyed by the address of
// one of the k*Key bytes below) so a sync pass that changes nothing allocates
// nothing.
CAShapeLayer *cachedShapeLayer(NSView *view, const void *key)
{
	CAShapeLayer *layer = objc_getAssociatedObject(view, key);
	if (!layer) {
		layer = [CAShapeLayer layer];
		// Sync passes run every frame; implicit CA animations would smear every
		// geometry change over a quarter second and lag the node tree.
		layer.actions = @{
			@"path" : [NSNull null],
			@"bounds" : [NSNull null],
			@"position" : [NSNull null],
			@"fillColor" : [NSNull null],
			@"strokeColor" : [NSNull null],
			@"shadowPath" : [NSNull null],
			@"shadowOpacity" : [NSNull null],
			@"hidden" : [NSNull null],
		};
		objc_setAssociatedObject(view, key, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return layer;
}

void dropShapeLayer(NSView *view, const void *key)
{
	CAShapeLayer *layer = objc_getAssociatedObject(view, key);
	if (!layer) return;
	if (layer.superlayer) [layer removeFromSuperlayer];
	if (view.layer.mask == layer) view.layer.mask = nil;
	objc_setAssociatedObject(view, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Association keys — the ADDRESSES identify the slot, so these must not be
// `const` (identical const objects are mergeable, which would alias the slots).
char kShapeMaskKey;    // CAShapeLayer installed as view.layer.mask
char kShapeFillKey;    // CAShapeLayer painting bg + border when a mask can't be used
char kShapeStrokeKey;  // CAShapeLayer drawing the border along a non-rect shape
char kInsetShadowKey;  // CAShapeLayer casting the inset box-shadow

CGColorRef createStyleCGColor(gea::embedded::ui::style_color_t color, uint8_t alpha)
{
	CGColor *base = gea::macos::rgb565ToCGColor(color);
	if (alpha == 255) return base;
	CGColor *faded = CGColorCreateCopyWithAlpha(base, alpha / 255.0);
	CGColorRelease(base);
	return faded;
}

// border-radius. Uniform circular radii stay on layer.cornerRadius (the cheap
// path every already-correct app takes); elliptical or per-corner radii get a
// CAShapeLayer, because cornerRadius is one scalar and physically cannot say
// rx != ry — a `border-radius: 50%` on a 360x34 box is an ellipse, not a
// stadium, and rendered square before this.
void applyCornerRadius(NSView *view, const gea::embedded::ui::Node &node, CGFloat w, CGFloat h,
                       bool blurred)
{
	const ResolvedRadii radii = resolveRadii(node, w, h);
	const CGFloat borderWidth = static_cast<CGFloat>(std::max(0, static_cast<int>(node.style.border_width)));

	if (radii.uniform) {
		dropShapeLayer(view, &kShapeMaskKey);
		dropShapeLayer(view, &kShapeFillKey);
		dropShapeLayer(view, &kShapeStrokeKey);
		view.layer.mask = nil;
		view.layer.cornerRadius = radii.rx[0];
		view.layer.masksToBounds = view.layer.cornerRadius > 0 || node.style.overflow == 1;
		return;
	}

	view.layer.cornerRadius = 0;
	const CGRect bounds = CGRectMake(0, 0, w, h);
	const bool flipped = view.isFlipped;

	if (blurred) {
		// A `filter: blur()` halo extends far past the element's box (CSS blurs
		// the rendered element, then composites). A layer mask is applied to the
		// layer's FINAL composite, so masking to the shape would shear the halo
		// off at the element edge. Paint the shape into a sublayer instead and
		// leave the view's own layer unclipped.
		//
		// The fill path is inset by half the border width and stroked with the
		// full width, so the stroke's outer edge lands exactly on the border box
		// — CSS borders are drawn inside the box — and one layer covers both.
		dropShapeLayer(view, &kShapeMaskKey);
		dropShapeLayer(view, &kShapeStrokeKey);
		view.layer.mask = nil;
		CAShapeLayer *fill = cachedShapeLayer(view, &kShapeFillKey);
		if (fill.superlayer != view.layer) [view.layer insertSublayer:fill atIndex:0];
		fill.frame = bounds;
		const CGFloat inset = borderWidth * 0.5;
		CGFloat rx[4];
		CGFloat ry[4];
		for (int i = 0; i < 4; ++i) {
			rx[i] = std::max<CGFloat>(0, radii.rx[i] - inset);
			ry[i] = std::max<CGFloat>(0, radii.ry[i] - inset);
		}
		CGPathRef path = createRoundedRectPath(CGRectInset(bounds, inset, inset), rx, ry, flipped);
		fill.path = path;
		CGPathRelease(path);
		if (node.style.has_bg) {
			CGColorRef bg = createStyleCGColor(node.style.bg_color, node.style.bg_alpha);
			fill.fillColor = bg;
			CGColorRelease(bg);
		} else {
			fill.fillColor = nil;
		}
		if (borderWidth > 0) {
			CGColorRef bc = createStyleCGColor(node.style.border_color, node.style.border_alpha);
			fill.strokeColor = bc;
			CGColorRelease(bc);
			fill.lineWidth = borderWidth;
		} else {
			fill.strokeColor = nil;
			fill.lineWidth = 0;
		}
		// The shape layer now owns background and border; the view's layer must
		// not paint a rectangular one underneath it.
		view.layer.backgroundColor = nil;
		view.layer.borderWidth = 0;
		view.layer.masksToBounds = NO;
		return;
	}

	dropShapeLayer(view, &kShapeFillKey);
	CAShapeLayer *mask = cachedShapeLayer(view, &kShapeMaskKey);
	mask.frame = bounds;
	CGPathRef path = createRoundedRectPath(bounds, radii.rx, radii.ry, flipped);
	mask.path = path;
	CGPathRelease(path);
	mask.fillColor = CGColorGetConstantColor(kCGColorBlack);
	if (view.layer.mask != mask) view.layer.mask = mask;
	// The mask already clips this layer and its subviews to the shape.
	view.layer.masksToBounds = node.style.overflow == 1;

	// layer.borderWidth strokes the RECTANGULAR bounds; under the mask that
	// leaves a border on the straight edges and nothing on the curves. Stroke
	// the real shape instead, inset by half the width so it stays inside the
	// border box (and so the mask does not eat its outer half).
	if (borderWidth > 0) {
		view.layer.borderWidth = 0;
		CAShapeLayer *stroke = cachedShapeLayer(view, &kShapeStrokeKey);
		if (stroke.superlayer != view.layer) [view.layer addSublayer:stroke];
		stroke.frame = bounds;
		const CGFloat inset = borderWidth * 0.5;
		CGFloat rx[4];
		CGFloat ry[4];
		for (int i = 0; i < 4; ++i) {
			rx[i] = std::max<CGFloat>(0, radii.rx[i] - inset);
			ry[i] = std::max<CGFloat>(0, radii.ry[i] - inset);
		}
		CGPathRef strokePath = createRoundedRectPath(CGRectInset(bounds, inset, inset), rx, ry, flipped);
		stroke.path = strokePath;
		CGPathRelease(strokePath);
		stroke.fillColor = nil;
		CGColorRef bc = createStyleCGColor(node.style.border_color, node.style.border_alpha);
		stroke.strokeColor = bc;
		CGColorRelease(bc);
		stroke.lineWidth = borderWidth;
	} else {
		dropShapeLayer(view, &kShapeStrokeKey);
	}
}

// filter: blur(<n>px). CALayer.filters applies Core Image to the layer AND its
// sublayers, which is CSS `filter`'s scope (the element plus its subtree).
// NSView refuses to route CIFilters into its backing layer unless
// layerUsesCoreImageFilters is set, and the halo is clipped unless the layer
// stops masking to its bounds.
void applyFilterBlur(NSView *view, const gea::embedded::ui::Node &node)
{
	const int radius = gea::embedded::ui::rstyle(node.style).filter_blur_radius;
	if (radius <= 0) {
		if (view.layer.filters != nil) view.layer.filters = nil;
		return;
	}
	if (!view.layerUsesCoreImageFilters) view.layerUsesCoreImageFilters = YES;
	view.layer.masksToBounds = NO;
	NSNumber *applied = [view.layer valueForKey:@"geaFilterBlurRadius"];
	if (applied && applied.intValue == radius && view.layer.filters.count == 1) return;
	CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
	if (!blur) return;
	[blur setDefaults];
	// CSS blur(<len>) is a Gaussian with standard deviation <len>, which is what
	// CIGaussianBlur's inputRadius is (it is the sigma, not the kernel extent).
	[blur setValue:@(static_cast<double>(radius)) forKey:@"inputRadius"];
	view.layer.filters = @[ blur ];
	[view.layer setValue:@(radius) forKey:@"geaFilterBlurRadius"];
}

// box-shadow. The engine's parser keeps only inset shadows (style.cpp
// parseInsetBoxShadow skips every non-inset layer and leaves box_shadow_alpha
// at 0), so an inset shadow is the only one a node can carry.
//
// CALayer's shadow casts OUTWARD from the layer's silhouette, so it cannot draw
// an inset shadow directly. The construction: a layer with no content at all
// whose shadowPath is (a rect well outside the box) MINUS (the box's own shape,
// moved by the offset and shrunk by the spread) — a ring whose shadow therefore
// falls INWARD — with masksToBounds clipping it to the element. shadowPath makes
// the shadow independent of the layer's (empty) contents, so nothing is painted;
// the subtraction is by opposite winding, see the path build below.
//
// Measured against the CSS model (sigma = blur/2, alpha, offset) on a
// `inset 0 8px 26px rgba(0,0,0,0.75)` probe: the rendered edge profile matched
// 255*(1 - a*Phi((offset-d)/sigma)) to within 3/255 at every depth d.
void applyBoxShadow(NSView *view, const gea::embedded::ui::Node &node, CGFloat w, CGFloat h)
{
	const auto &rare = gea::embedded::ui::rstyle(node.style);
	if (!rare.box_shadow_inset || rare.box_shadow_alpha == 0 || w <= 0 || h <= 0) {
		dropShapeLayer(view, &kInsetShadowKey);
		return;
	}

	const CGFloat blur = std::max(0, static_cast<int>(rare.box_shadow_blur_radius));
	const CGFloat spread = static_cast<CGFloat>(rare.box_shadow_spread);
	const CGFloat offsetX = static_cast<CGFloat>(rare.box_shadow_offset_x);
	const CGFloat offsetY = static_cast<CGFloat>(rare.box_shadow_offset_y);
	const CGRect bounds = CGRectMake(0, 0, w, h);
	const bool flipped = view.isFlipped;

	CAShapeLayer *shadow = cachedShapeLayer(view, &kInsetShadowKey);
	// Above the background (which lives on view.layer itself), below the
	// children — the CSS paint order for an inset shadow.
	if (shadow.superlayer != view.layer) [view.layer insertSublayer:shadow atIndex:0];
	shadow.frame = bounds;
	shadow.masksToBounds = YES;
	shadow.fillColor = nil;
	shadow.strokeColor = nil;

	const ResolvedRadii radii = resolveRadii(node, w, h);
	// The shadow-casting hole: the padding box shrunk by the spread and moved by
	// the CSS offset. AppKit's y grows upward on an unflipped view, so a
	// positive CSS offsetY (downward) is a negative dy here.
	const CGFloat dy = flipped ? offsetY : -offsetY;
	CGRect hole = CGRectInset(bounds, spread, spread);
	hole = CGRectOffset(hole, offsetX, dy);
	CGFloat rx[4];
	CGFloat ry[4];
	for (int i = 0; i < 4; ++i) {
		rx[i] = std::max<CGFloat>(0, radii.rx[i] - spread);
		ry[i] = std::max<CGFloat>(0, radii.ry[i] - spread);
	}
	const CGFloat margin = blur * 3 + std::fabs(offsetX) + std::fabs(offsetY) + std::fabs(spread) + 8;
	// CALayer fills shadowPath with the NON-ZERO winding rule, so the hole only
	// survives if it winds opposite to the outer rect. createRoundedRectPath
	// runs counter-clockwise, so the outer rect is emitted clockwise by hand —
	// CGPathAddRect would wind the same way and blanket the whole view in
	// shadow (measured: a 0.75-alpha inset shadow flooded the entire element).
	const CGRect outer = CGRectInset(bounds, -margin, -margin);
	CGMutablePathRef ring = CGPathCreateMutable();
	CGPathMoveToPoint(ring, NULL, CGRectGetMinX(outer), CGRectGetMinY(outer));
	CGPathAddLineToPoint(ring, NULL, CGRectGetMinX(outer), CGRectGetMaxY(outer));
	CGPathAddLineToPoint(ring, NULL, CGRectGetMaxX(outer), CGRectGetMaxY(outer));
	CGPathAddLineToPoint(ring, NULL, CGRectGetMaxX(outer), CGRectGetMinY(outer));
	CGPathCloseSubpath(ring);
	if (hole.size.width > 0 && hole.size.height > 0) {
		CGPathRef inner = createRoundedRectPath(hole, rx, ry, flipped);
		CGPathAddPath(ring, NULL, inner);
		CGPathRelease(inner);
	}
	shadow.shadowPath = ring;
	CGPathRelease(ring);
	CGColorRef color = createStyleCGColor(rare.box_shadow_color, 255);
	shadow.shadowColor = color;
	CGColorRelease(color);
	// CSS blur-radius is twice the Gaussian sigma; CALayer.shadowRadius is the
	// sigma. Same convention the web platform uses.
	shadow.shadowRadius = blur * 0.5;
	shadow.shadowOffset = CGSizeZero;  // already folded into the hole's position
	shadow.shadowOpacity = rare.box_shadow_alpha / 255.0;
}

void applyViewStyle(NSView *view, const gea::embedded::ui::Node &node,
                    int parentAbsX, int parentAbsY, int parentHeight)
{
	// layout.x/y are ABSOLUTE document coordinates after resolveAbsoluteCoords.
	// Convert to coordinates relative to the parent NSView, then y-flip against
	// the parent's height to land in AppKit's (default-unflipped) bottom-left
	// origin space.
	const int relX = node.layout.x - parentAbsX;
	const int w = node.layout.width;
	const int h = node.layout.height;
	const int relY = node.layout.y - parentAbsY;
	const CGFloat yBottom = static_cast<CGFloat>(parentHeight - relY - h);

	view.frame = NSMakeRect(relX, yBottom, w, h);

	// `filter: blur()` needs CIFilter-backed layer filters, and NSView rebuilds
	// its backing layer when this flag flips — so it has to be set before
	// anything (background, mask, shape sublayers) is put on that layer.
	if (gea::embedded::ui::rstyle(node.style).filter_blur_radius > 0 && !view.layerUsesCoreImageFilters)
		view.layerUsesCoreImageFilters = YES;

	// NSVisualEffectView IS the background — the system renders the chosen
	// material into the view's bounds, and a layer-level backgroundColor on
	// top would defeat the vibrancy entirely. Skip the CSS background-color
	// channel for these views; corner radius / border still apply below.
	if (![view isKindOfClass:[NSVisualEffectView class]]) {
		if (node.style.has_bg) {
			// rgb565 carries no alpha channel — the style system keeps the CSS
			// alpha in bg_alpha (255 = opaque). Without honoring it, translucent
			// backgrounds (weather's rgba(255,255,255,0.12) city chips) painted
			// fully opaque.
			CGColor *bg = gea::macos::rgb565ToCGColor(node.style.bg_color);
			if (node.style.bg_alpha != 255) {
				CGColor *faded = CGColorCreateCopyWithAlpha(bg, node.style.bg_alpha / 255.0);
				CGColorRelease(bg);
				bg = faded;
			}
			view.layer.backgroundColor = bg;
			CGColorRelease(bg);
		} else {
			view.layer.backgroundColor = nil;
		}
	}

	view.alphaValue = static_cast<CGFloat>(node.style.opacity) / 255.0;
	view.hidden = (node.style.display == 1);

	// Border (border_alpha carries the CSS alpha, same as bg_alpha above).
	if (node.style.border_width > 0) {
		view.layer.borderWidth = node.style.border_width;
		CGColor *bc = gea::macos::rgb565ToCGColor(node.style.border_color);
		if (node.style.border_alpha != 255) {
			CGColor *faded = CGColorCreateCopyWithAlpha(bc, node.style.border_alpha / 255.0);
			CGColorRelease(bc);
			bc = faded;
		}
		view.layer.borderColor = bc;
		CGColorRelease(bc);
	} else {
		view.layer.borderWidth = 0;
	}

	// Corner radius. Uniform circular radii ride layer.cornerRadius; percent
	// radii on a non-square box (rx != ry) and per-corner radii need a real
	// path, which applyCornerRadius installs as a CAShapeLayer. It also takes
	// over background/border painting on the blurred path, so it must run after
	// both are set above.
	const bool nodeIsBlurred = gea::embedded::ui::rstyle(node.style).filter_blur_radius > 0;
	applyCornerRadius(view, node, w, h, nodeIsBlurred);
	applyBoxShadow(view, node, w, h);

	// Rotation. transform_rotate is stored as TENTHS of degrees (see
	// style.cpp's numericRotateTenths — `degrees * 10`). CSS rotate is
	// clockwise-positive; in an unflipped NSView (Y-up), CATransform3D's
	// Z-rotation is counter-clockwise-positive, so negate.
	//
	// We do NOT touch view.layer.anchorPoint to position the rotation pivot
	// — AppKit owns the anchor for layer-backed NSViews and silently keeps
	// it at (0, 0) (the layer's bottom-left in local coords), so any
	// anchorPoint we set is reverted. CALayer applies the layer's transform
	// AS IF the anchor were the origin, which means our rotation pivots
	// around layer-local (0, 0) by default. To pivot around the CSS
	// transform-origin (px, py) in layer-local coords instead, compose
	// translate(px,py) · rotate · translate(−px,−py): bring the pivot to
	// the anchor, rotate, then send it back.
	if (gea::embedded::ui::rstyle(node.style).transform_rotate != 0) {
		const CGFloat degrees = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_rotate) / 10.0;
		const CGFloat radians = -degrees * (M_PI / 180.0);
		// transform_origin is stored per-mille (0..1000) of the layer's
		// bounds, in CSS coords (Y top→bottom). Convert to NSView local
		// coords (Y bottom→top) so the pivot lines up with the visual
		// position the CSS author intended.
		const CGFloat px = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_origin_x) / 1000.0 * w;
		const CGFloat cssPivotY = static_cast<CGFloat>(gea::embedded::ui::rstyle(node.style).transform_origin_y) / 1000.0 * h;
		const CGFloat py = h - cssPivotY;
		CATransform3D t = CATransform3DIdentity;
		t = CATransform3DTranslate(t, px, py, 0);
		t = CATransform3DRotate(t, radians, 0, 0, 1);
		t = CATransform3DTranslate(t, -px, -py, 0);
		view.layer.transform = t;
	} else if (!CATransform3DIsIdentity(view.layer.transform)) {
		view.layer.transform = CATransform3DIdentity;
	}

	// Last: the blur clears masksToBounds so its halo can spread, and every
	// branch above may have set it.
	applyFilterBlur(view, node);
}

void addTextDecorationAttributes(NSMutableDictionary *attrs, int textDecoration)
{
	if (!attrs) return;
	NSNumber *style = @((NSInteger)NSUnderlineStyleSingle);
	if (textDecoration == 1) {
		attrs[NSUnderlineStyleAttributeName] = style;
	} else if (textDecoration == 2) {
		attrs[NSStrikethroughStyleAttributeName] = style;
	}
}

NSMutableDictionary *textAttributes(NSFont *font, NSColor *color, int textDecoration)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	attrs[NSFontAttributeName] = font ?: [NSFont systemFontOfSize:12];
	attrs[NSForegroundColorAttributeName] = color ?: [NSColor labelColor];
	addTextDecorationAttributes(attrs, textDecoration);
	return attrs;
}

bool attributedStringHasTextDecoration(NSAttributedString *value)
{
	if (!value || value.length == 0) return false;
	return [value attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:nil] != nil ||
	       [value attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:nil] != nil;
}

void applyTextProps(NSTextField *tf, const gea::embedded::ui::Node &node)
{
	NSString *raw = [NSString stringWithUTF8String:(node.text.empty() ? "" : node.text.c_str())];
	NSFont *font = gea::macos::fontForId(node.style.font_id, node.style.font_size);
	NSColor *color = gea::macos::rgb565ToNSColor(node.style.text_color);

	NSTextAlignment alignment;
	switch (node.style.text_align) {
	case 1: alignment = NSTextAlignmentCenter; break;
	case 2: alignment = NSTextAlignmentRight; break;
	default: alignment = NSTextAlignmentLeft;
	}

	// Use the same attributes the host measurement hook (font_registry.mm's
	// gea_host_measure_text) uses — same font, same break mode, default
	// kerning. Identical attributes guarantee the rendered NSTextField has
	// exactly the width/height the framework's layout engine allocated for
	// the text node, so titles never end up with a gap below them from
	// over-allocation and long labels never overflow into clipped territory
	// from under-allocation.
	//
	// Alignment is deliberately NOT one of those attributes. An
	// NSParagraphStyle whose `alignment` is NSTextAlignmentCenter makes
	// NSTextFieldCell demand FOUR MORE POINTS of width for the same string
	// (measured: "Reset"/Inter 15 needs 44pt with a natural or left/right
	// paragraph and 48pt with a centred one). The measurement hook sets only
	// `lineBreakMode`, so every centre-aligned label was laid out 4pt narrower
	// than AppKit would draw it, `wraps = YES` broke the word onto a second
	// line, and the field's one-line height hid it: "COUNTER" rendered as
	// "COUNTE", "Reset" as "Rese", "Ready" as "Read". Single-glyph labels
	// survived only because their boxes had more than 4pt of slack.
	//
	// `tf.alignment` below still centres the text and costs nothing, because
	// the cell -- not the paragraph style -- applies it. Keep alignment there.
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	const CGFloat availableWidth = node.layout.width > 0 ? node.layout.width : CGFLOAT_MAX;
	paragraph.lineBreakMode = gea::macos::lineBreakModeForText(raw, font, availableWidth);
	NSMutableDictionary *attrs = textAttributes(font ?: [NSFont systemFontOfSize:node.style.font_size > 0 ? node.style.font_size : 12],
	                                            color,
	                                            node.style.text_decoration);
	attrs[NSParagraphStyleAttributeName] = paragraph;
	NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:raw attributes:attrs];
	if (![tf.attributedStringValue isEqualToAttributedString:attributed]) {
		tf.attributedStringValue = attributed;
	}
	tf.alignment = alignment;
	tf.textColor = color;
	tf.font = font;
}

void applyInputProps(GeaInputField *tf, const gea::embedded::ui::Node &node, int nodeId)
{
	using gea::embedded::ui::Tree;
	tf.nodeId = nodeId;

	// The store drives `value` via the framework's reactive-attribute machinery,
	// which writes to `node.setAttribute("value", ...)`. Mirror that to the
	// field's stringValue — but only when the displayed string actually differs
	// from the desired value. While the user is typing, `controlTextDidChange:`
	// keeps `value` in sync with every keystroke, so `tf.stringValue == desired`
	// and we skip the redundant assignment (which would otherwise reset the
	// caret/selection). When a programmatic change fires (note selection, new
	// note), the values genuinely differ and we always update — regardless of
	// whether the field is currently focused — so the editor clears correctly.
	auto &tree = Tree::instance();
	const char *value = tree.getAttribute(nodeId, "value");
	tf.textColor = gea::macos::rgb565ToNSColor(node.style.text_color);
	tf.font = gea::macos::fontForId(node.style.font_id, node.style.font_size);
	switch (node.style.text_align) {
	case 1: tf.alignment = NSTextAlignmentCenter; break;
	case 2: tf.alignment = NSTextAlignmentRight; break;
	default: tf.alignment = NSTextAlignmentLeft;
	}
	NSMutableDictionary *attrs = textAttributes(tf.font, tf.textColor, node.style.text_decoration);

	if (value) {
		NSString *desired = [NSString stringWithUTF8String:value];
		if (node.style.text_decoration != 0) {
			NSAttributedString *decoratedValue = [[NSAttributedString alloc] initWithString:desired attributes:attrs];
			if (![tf.attributedStringValue isEqualToAttributedString:decoratedValue]) tf.attributedStringValue = decoratedValue;
		} else if (![tf.stringValue isEqualToString:desired] ||
		           attributedStringHasTextDecoration(tf.attributedStringValue)) {
			tf.stringValue = desired;
		}
	}

	const char *placeholder = tree.getAttribute(nodeId, "placeholder");
	if (placeholder && placeholder[0]) {
		NSString *p = [NSString stringWithUTF8String:placeholder];
		if (![tf.placeholderString isEqualToString:p]) tf.placeholderString = p;
	}
}

void applySliderProps(GeaSlider *sl, const gea::embedded::ui::Node &node, int nodeId)
{
	(void)node;
	using gea::embedded::ui::Tree;
	auto &tree = Tree::instance();
	sl.nodeId = nodeId;
	const char *minA = tree.getAttribute(nodeId, "min");
	const char *maxA = tree.getAttribute(nodeId, "max");
	if (minA && minA[0]) sl.minValue = atof(minA);
	if (maxA && maxA[0]) sl.maxValue = atof(maxA);
	// `value` is driven reactively; atof ignores a trailing unit (e.g. "75%").
	// Don't overwrite the thumb while the user is actively dragging.
	const char *value = tree.getAttribute(nodeId, "value");
	if (value && value[0] && !sl.geaDragging) {
		const double v = atof(value);
		if (sl.doubleValue != v) sl.doubleValue = v;
	}
}

void applySwitchProps(GeaSwitch *sw, const gea::embedded::ui::Node &node, int nodeId)
{
	(void)node;
	using gea::embedded::ui::Tree;
	auto &tree = Tree::instance();
	sw.nodeId = nodeId;
	const char *checked = tree.getAttribute(nodeId, "checked");
	const bool hasChecked = tree.hasAttribute(nodeId, "checked");
	const bool explicitlyOff = checked && (std::strcmp(checked, "false") == 0 || std::strcmp(checked, "0") == 0);
	const bool on = hasChecked && !explicitlyOff;
	const NSControlStateValue want = on ? NSControlStateValueOn : NSControlStateValueOff;
	if (sw.state != want) sw.state = want;
}

void applySymbolProps(NSImageView *iv, const gea::embedded::ui::Node &node, int nodeId)
{
	using gea::embedded::ui::Tree;
	Tree &tree = Tree::instance();
	const char *symbol = tree.getAttribute(nodeId, "data-symbol");
	NSNumber *currentSym = objc_getAssociatedObject(iv, "gea.symbol_name_hash");
	const NSUInteger wantHash = symbol ? [[NSString stringWithUTF8String:symbol] hash] : 0;
	if (!currentSym || currentSym.unsignedIntegerValue != wantHash) {
		if (symbol && symbol[0]) {
			NSString *name = [NSString stringWithUTF8String:symbol];
			NSImage *img = nil;
			if (@available(macOS 11.0, *)) {
				img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:name];
			}
			iv.image = img;
		} else {
			iv.image = nil;
		}
		objc_setAssociatedObject(iv, "gea.symbol_name_hash", @(wantHash), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	// SF Symbols render as template images; tint with the node's CSS color
	// (falls back to the system label color so they adapt to dark mode).
	if (node.style.text_color != 0) {
		iv.contentTintColor = gea::macos::rgb565ToNSColor(node.style.text_color);
	} else {
		iv.contentTintColor = [NSColor labelColor];
	}
}

void applyVibrancyProps(NSVisualEffectView *ve, const gea::embedded::ui::Node &node, int nodeId)
{
	(void)node;
	using gea::embedded::ui::Tree;
	Tree &tree = Tree::instance();
	const char *material = tree.getAttribute(nodeId, "data-material");
	const char *blending = tree.getAttribute(nodeId, "data-blending");
	const char *appearance = tree.getAttribute(nodeId, "data-appearance");
	const NSVisualEffectMaterial wantMaterial = vibrancyMaterialFromString(material);
	const NSVisualEffectBlendingMode wantBlending = vibrancyBlendingFromString(blending);
	if (ve.material != wantMaterial) ve.material = wantMaterial;
	if (ve.blendingMode != wantBlending) ve.blendingMode = wantBlending;
	if (appearance && appearance[0]) {
		NSAppearance *want = nil;
		if (std::strcmp(appearance, "dark") == 0) {
			want = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
		} else if (std::strcmp(appearance, "light") == 0) {
			want = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		}
		if (want && ve.appearance != want) ve.appearance = want;
	}
}

void applyTextAreaProps(NSScrollView *sv, const gea::embedded::ui::Node &node, int nodeId)
{
	using gea::embedded::ui::Tree;
	Tree &tree = Tree::instance();
	GeaTextAreaView *tv = objc_getAssociatedObject(sv, "gea.text_view");
	if (!tv) return;
	tv.nodeId = nodeId;

	NSFont *font = gea::macos::fontForId(node.style.font_id, node.style.font_size > 0 ? node.style.font_size : 14);
	NSColor *color = gea::macos::rgb565ToNSColor(node.style.text_color);
	tv.font = font ?: [NSFont systemFontOfSize:14];
	tv.textColor = color ?: [NSColor labelColor];
	tv.insertionPointColor = tv.textColor;

	// Mirror the store's `value` attribute to the NSTextView — but only when
	// the displayed string actually differs. While typing, `textDidChange:`
	// keeps `value` in sync with every keystroke so `tv.string == desired` and
	// we skip the redundant assignment (which would reset selection/layout).
	// Programmatic changes (new note, note selection) produce a genuine diff
	// and always win — regardless of focus — so the body clears correctly.
	const char *value = tree.getAttribute(nodeId, "value");
	if (value) {
		NSString *desired = [NSString stringWithUTF8String:value] ?: @"";
		if (![tv.string isEqualToString:desired]) {
			tv.suppressChangeNotification = YES;
			[tv setString:desired];
			tv.suppressChangeNotification = NO;
		}
	}

	// Update font/color of already-laid-out text. NSTextView caches these on
	// the typingAttributes for the next inserted run, so users get the same
	// appearance when they keep typing.
	tv.typingAttributes = @{
		NSFontAttributeName: tv.font,
		NSForegroundColorAttributeName: tv.textColor,
	};
}

void applyButtonProps(NSButton *btn, const gea::embedded::ui::Node &node, int nodeId)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();

	// Title from the first Text child, if any. JSX <Button>label</Button>
	// produces a Button with a text child.
	NSString *title = @"";
	for (int child = node.first_child; child >= 0; child = tree.node(child).next_sibling) {
		const Node &cn = tree.node(child);
		if (cn.type == NodeType::Text && !cn.text.empty()) {
			title = [NSString stringWithUTF8String:cn.text.c_str()];
			break;
		}
	}
	// Buttons whose label is composed of ELEMENT children (weather's city
	// chips: <button><span>name</span><span>temp</span></button>) have no
	// direct Text child, and the renderer deliberately never descends into
	// buttons — so their title vanished entirely. Collect descendant text in
	// document order instead, joined with spaces.
	if (title.length == 0) {
		NSMutableArray<NSString *> *parts = [NSMutableArray array];
		std::vector<int> stack;
		for (int child = node.first_child; child >= 0; child = tree.node(child).next_sibling) stack.push_back(child);
		std::reverse(stack.begin(), stack.end());
		while (!stack.empty()) {
			const int id = stack.back();
			stack.pop_back();
			const Node &cn = tree.node(id);
			if (cn.type == NodeType::Text && !cn.text.empty()) {
				[parts addObject:[NSString stringWithUTF8String:cn.text.c_str()] ?: @""];
			}
			std::vector<int> children;
			for (int child = cn.first_child; child >= 0; child = tree.node(child).next_sibling) children.push_back(child);
			for (auto it = children.rbegin(); it != children.rend(); ++it) stack.push_back(*it);
		}
		title = [parts componentsJoinedByString:@" "];
	}

	// A CSS background on the button means the app styles the chip itself
	// (weather's translucent city chips). The default Aqua bezel would paint
	// opaque white over that background and pin the title to black — go
	// borderless so applyViewStyle's layer background/corner radius show, and
	// carry the node's text color/font into an attributed title. Plain
	// unstyled <button>s keep the native bezel and title exactly as before.
	const bool cssStyled = node.style.has_bg;
	if (btn.bordered != static_cast<BOOL>(!cssStyled)) btn.bordered = !cssStyled;
	if (cssStyled) {
		NSFont *font = gea::macos::fontForId(node.style.font_id, node.style.font_size);
		NSColor *color = node.style.text_color != 0 ? gea::macos::rgb565ToNSColor(node.style.text_color)
		                                            : [NSColor labelColor];
		NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
		paragraph.alignment = NSTextAlignmentCenter;
		NSDictionary *attrs = @{
			NSFontAttributeName: font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]],
			NSForegroundColorAttributeName: color,
			NSParagraphStyleAttributeName: paragraph,
		};
		NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:title attributes:attrs];
		if (![btn.attributedTitle isEqualToAttributedString:attributed]) btn.attributedTitle = attributed;
	} else {
		if (![btn.title isEqualToString:title]) btn.title = title;
	}

	PressBridge *bridge = objc_getAssociatedObject(btn, "gea.press_bridge");
	if (bridge) bridge.nodeId = nodeId;
}

void ensureViewClickRecognizer(NSView *view, int nodeId, bool wantsClick)
{
	PressBridge *bridge = objc_getAssociatedObject(view, "gea.press_bridge");
	BOOL hasRecognizer = NO;
	for (NSGestureRecognizer *gr in view.gestureRecognizers) {
		if ([gr isKindOfClass:[NSClickGestureRecognizer class]]) { hasRecognizer = YES; break; }
	}
	if (wantsClick) {
		if (!bridge) {
			bridge = [[PressBridge alloc] init];
			objc_setAssociatedObject(view, "gea.press_bridge", bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		bridge.nodeId = nodeId;
		if (!hasRecognizer) {
			NSClickGestureRecognizer *gr =
			    [[NSClickGestureRecognizer alloc] initWithTarget:bridge action:@selector(fire:)];
			[view addGestureRecognizer:gr];
		}
	}
	// If wantsClick became false, leave the recognizer in place — toggling
	// it per-frame would churn AppKit state. Real apps rarely toggle
	// pressId at runtime.
}

void applyImageProps(NSImageView *iv, const gea::embedded::ui::Node &node)
{
	// Re-decode when image_id changes; otherwise leave the current NSImage in
	// place to avoid rebuilding the bitmap every frame. We stash the last
	// imageId on the view via associated object.
	NSNumber *currentId = objc_getAssociatedObject(iv, "gea.image_id");
	if (!currentId || currentId.intValue != node.image_id) {
		iv.image = gea::macos::imageForId(node.image_id);
		objc_setAssociatedObject(iv, "gea.image_id", @(node.image_id),
		                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	switch (node.style.image_fit) {
	case 0: iv.imageScaling = NSImageScaleAxesIndependently; break;
	case 1: iv.imageScaling = NSImageScaleProportionallyUpOrDown; break;
	case 2: iv.imageScaling = NSImageScaleProportionallyUpOrDown; break;  // "cover" ~ fit
	case 3: iv.imageScaling = NSImageScaleNone; break;
	case 4: iv.imageScaling = NSImageScaleProportionallyDown; break;
	default: iv.imageScaling = NSImageScaleAxesIndependently;
	}
}

void applyScrollContentSize(NSScrollView *sv, const gea::embedded::ui::Node &node)
{
	NSView *content = sv.documentView;
	if (!content) return;
	// The engine reserves no scrollbar gutter: every target lays content out
	// across the container's full width and draws its scroller over it. A
	// legacy (always-shown) NSScroller takes its width out of the clip instead,
	// hiding that strip of the layout and leaving the document sideways play, so
	// the scroller stays in the overlay style.
	if (sv.scrollerStyle != NSScrollerStyleOverlay) sv.scrollerStyle = NSScrollerStyleOverlay;
	const CGFloat w = node.layout.width;
	const CGFloat h = node.layout.scroll_content_height > 0
	                      ? node.layout.scroll_content_height
	                      : node.layout.height;
	// documentView always sized to the full scroll content; NSScrollView's
	// own scrollers handle the visible window. We don't apply the tree's
	// scroll_y here — AppKit owns the scroll position via NSScrollView.
	if (content.frame.size.width != w || content.frame.size.height != h) {
		content.frame = NSMakeRect(0, 0, w, h);
	}
}

void applyCanvasProps(GeaCanvasView *cv, const gea::embedded::ui::Node &node, int nodeId)
{
	cv.nodeId = nodeId;
	// Always redraw for now — the canvas pixel buffer can change every frame
	// (e.g. an animation app). Per-frame setNeedsDisplay forces drawRect: to
	// pick up the latest pixels. A future optimisation would gate this on
	// canvas->dirty() to avoid full redraws when nothing changed.
	(void)node;
	[cv setNeedsDisplay:YES];
}

void applyTypeSpecificProps(NSView *view, const gea::embedded::ui::Node &node, int nodeId)
{
	using gea::embedded::ui::NodeType;
	if (node.type == NodeType::Text) {
		applyTextProps((NSTextField *)view, node);
	} else if (node.type == NodeType::Button) {
		applyButtonProps((NSButton *)view, node, nodeId);
	} else if (node.type == NodeType::Image) {
		applyImageProps((NSImageView *)view, node);
	} else if (node.type == NodeType::Canvas) {
		applyCanvasProps((GeaCanvasView *)view, node, nodeId);
	} else if ([view isKindOfClass:[GeaSlider class]]) {
		applySliderProps((GeaSlider *)view, node, nodeId);
	} else if ([view isKindOfClass:[GeaSwitch class]]) {
		applySwitchProps((GeaSwitch *)view, node, nodeId);
	} else if ([view isKindOfClass:[GeaInputField class]]) {
		applyInputProps((GeaInputField *)view, node, nodeId);
	} else if (objc_getAssociatedObject(view, "gea.is_symbol")) {
		applySymbolProps((NSImageView *)view, node, nodeId);
	} else if ([view isKindOfClass:[NSVisualEffectView class]]) {
		applyVibrancyProps((NSVisualEffectView *)view, node, nodeId);
	} else if (isScrollView(view) && objc_getAssociatedObject(view, "gea.text_view")) {
		// `<textarea>` materializes as NSScrollView whose documentView is a
		// GeaTextAreaView. Apply the editor-style props (font, value) rather
		// than the generic scroll-content size dance, because the textarea's
		// document view manages its own scrollable height.
		applyTextAreaProps((NSScrollView *)view, node, nodeId);
	} else if (isScrollView(view)) {
		// Both NodeType::VirtualList and overflow:scroll Views land here.
		applyScrollContentSize((NSScrollView *)view, node);
	}

	// Per-View click recognizers don't fit the framework's event-delegation
	// pattern (listeners are bound on document.body and check event.target).
	// Click handling is centralized in GeaRootClickBridge installed on the
	// root NSView in MacosRenderer::sync — it hit-tests the click and
	// dispatches with the deepest matching nodeId.
	(void)nodeId;
}

bool viewMatchesNode(NSView *view, const gea::embedded::ui::Node &node,
                     const char *tagName, const char *inputType)
{
	using gea::embedded::ui::NodeType;
	if (!view) return false;
	const bool isSymbolView = objc_getAssociatedObject(view, "gea.is_symbol") != nil;
	const bool isTextAreaView = isScrollView(view) && objc_getAssociatedObject(view, "gea.text_view") != nil;
	const bool isPlainScrollView = isScrollView(view) && !isTextAreaView;

	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "input") == 0) {
		if (inputType && std::strcmp(inputType, "range") == 0) return [view isKindOfClass:[GeaSlider class]];
		if (inputType && std::strcmp(inputType, "checkbox") == 0) return [view isKindOfClass:[GeaSwitch class]];
		return [view isKindOfClass:[GeaInputField class]];
	}
	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "textarea") == 0) {
		return isTextAreaView;
	}
	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "vibrancy") == 0) {
		return [view isKindOfClass:[NSVisualEffectView class]];
	}
	if (node.type == NodeType::View && tagName && std::strcmp(tagName, "symbol") == 0) {
		return [view isKindOfClass:[NSImageView class]] && isSymbolView;
	}
	if (node.type == NodeType::VirtualList ||
	    (node.type == NodeType::View && node.style.overflow == 2)) {
		return isPlainScrollView;
	}

	switch (node.type) {
	case NodeType::Text: return [view isKindOfClass:[GeaLabelTextField class]];
	case NodeType::Button: return [view isKindOfClass:[NSButton class]];
	case NodeType::Image: return [view isKindOfClass:[NSImageView class]] && !isSymbolView;
	case NodeType::Canvas: return [view isKindOfClass:[GeaCanvasView class]];
	case NodeType::View:
	default:
		return [view isKindOfClass:[NSView class]] &&
		       ![view isKindOfClass:[NSTextField class]] &&
		       ![view isKindOfClass:[NSButton class]] &&
		       ![view isKindOfClass:[NSImageView class]] &&
		       ![view isKindOfClass:[NSScrollView class]] &&
		       ![view isKindOfClass:[NSVisualEffectView class]] &&
		       ![view isKindOfClass:[GeaCanvasView class]] &&
		       ![view isKindOfClass:[GeaSlider class]] &&
		       ![view isKindOfClass:[GeaSwitch class]] &&
		       ![view isKindOfClass:[GeaInputField class]];
	}
}

NSView *ensureViewForNode(int nodeId, const gea::embedded::ui::Node &node)
{
	NSNumber *key = @(nodeId);
	NSView *view = nodeIdToView()[key];
	const char *tagName = gea::embedded::ui::Tree::instance().tagName(nodeId);
	const char *inputType = gea::embedded::ui::Tree::instance().getAttribute(nodeId, "type");
	if (view && !viewMatchesNode(view, node, tagName, inputType)) {
		[view removeFromSuperview];
		[nodeIdToView() removeObjectForKey:key];
		view = nil;
	}
	if (view) return view;
	view = makeViewForType(node.type, tagName, node.style, inputType);
	// Stamp the nodeId on the view so the root-level click handler can map
	// hit-tested NSViews back to tree nodes. Used by GeaRootClickBridge to
	// dispatch with the deepest matching node's id (event delegation —
	// the framework binds listeners on document.body and checks event.target).
	objc_setAssociatedObject(view, "gea.node_id", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	nodeIdToView()[key] = view;
	return view;
}


// Returns true if `nodeId` is a paragraph-style inline-flow container — a
// <p> or heading whose children should AppKit-render as a single attributed
// string with real inline flow. The framework's flex layout otherwise treats
// each child as its own flex item, squeezing inline spans into 22-px slots
// that vertically chop "div" into "di" / "v".
//
// We key off tag_name rather than tree shape because the framework collapses
// `<span>text</span>` into a bare Text node — so a `<div>` containing
// `<span class="title">A</span><p>body</p>` looks structurally identical to
// a `<p>raw text <span class="x">x</span> more</p>` after lowering. tag_name
// is the only signal that survives: <p> / <h1>-<h6> mean inline flow, <div>
// means block container.
bool nodeIsInlineComposable(int nodeId)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return false;
	const Node &node = tree.node(nodeId);
	if (node.first_child < 0) return false;
	const char *tag = tree.tagName(nodeId);
	if (!tag) return false;
	const bool inlineTag = (std::strcmp(tag, "p") == 0)  ||
	                       (std::strcmp(tag, "h1") == 0) ||
	                       (std::strcmp(tag, "h2") == 0) ||
	                       (std::strcmp(tag, "h3") == 0) ||
	                       (std::strcmp(tag, "h4") == 0) ||
	                       (std::strcmp(tag, "h5") == 0) ||
	                       (std::strcmp(tag, "h6") == 0);
	if (!inlineTag) return false;
	// Still require >1 child — a paragraph with a single text run renders
	// fine via the normal Text-node path, no composition gymnastics needed.
	int count = 0;
	for (int c = node.first_child; c >= 0; c = tree.node(c).next_sibling) {
		const Node &cn = tree.node(c);
		// Anything beyond inline-style content (Text, or a View whose own
		// descendants are all Text) means this isn't a pure inline run.
		if (cn.type == NodeType::Text) { ++count; continue; }
		if (cn.type != NodeType::View) return false;
		if (cn.first_child < 0) return false;
		for (int gc = cn.first_child; gc >= 0; gc = tree.node(gc).next_sibling) {
			if (tree.node(gc).type != NodeType::Text) return false;
		}
		++count;
	}
	return count >= 2;
}

// Walk `nodeId`'s inline subtree and append run-attributed text. `inheritColor`
// supplies the foreground color when the child doesn't set its own. Text
// decoration stays per run so AppKit can place underline/strike natively.
void appendInlineRuns(NSMutableAttributedString *out, int nodeId,
                      NSFont *parentFont, NSColor *parentColor)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	const Node &node = tree.node(nodeId);
	if (node.type == NodeType::Text) {
		if (node.text.empty()) return;
		NSString *str = [NSString stringWithUTF8String:node.text.c_str()] ?: @"";
		NSColor *col = parentColor;
		NSFont *font = parentFont;
		// Text node style is already resolved by the framework's CSS cascade
		// (color/font_id/font_size on a text child come from its <span>
		// ancestor's class). When the framework has filled them in we use
		// them; otherwise we keep the parent's value as the inherited default.
		if (node.style.text_color != 0) {
			col = gea::macos::rgb565ToNSColor(node.style.text_color);
		}
		NSFont *resolved = gea::macos::fontForId(node.style.font_id, node.style.font_size);
		if (resolved) font = resolved;
		NSMutableDictionary *attrs = textAttributes(font, col, node.style.text_decoration);
		[out appendAttributedString:[[NSAttributedString alloc] initWithString:str attributes:attrs]];
		return;
	}
	// Inline View (span). Resolve its own color/font once and recurse into
	// children with those as the new inherited values.
	NSColor *col = parentColor;
	NSFont *font = parentFont;
	if (node.style.text_color != 0) {
		col = gea::macos::rgb565ToNSColor(node.style.text_color);
	}
	NSFont *resolved = gea::macos::fontForId(node.style.font_id, node.style.font_size);
	if (resolved) font = resolved;
	for (int c = node.first_child; c >= 0; c = tree.node(c).next_sibling) {
		appendInlineRuns(out, c, font, col);
	}
}

// Make the parent node render as a single NSTextField holding the composite
// attributed string built from all its inline descendants. Hides any per-child
// NSViews so they don't double-render on top. Returns the field for sizing.
NSTextField *renderInlineComposition(int nodeId, NSView *parentNSView,
                                     int parentAbsX, int parentAbsY, int parentHeight,
                                     NSMutableSet<NSNumber *> *unseen)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	const Node &node = tree.node(nodeId);

	// Reuse a single NSTextField stashed on the parent's NSView so re-renders
	// don't pile up subviews. Tagged with the parent nodeId so unseen-cleanup
	// doesn't sweep it.
	GeaLabelTextField *field = objc_getAssociatedObject(parentNSView, "gea.inline_field");
	if (!field) {
		field = [[GeaLabelTextField alloc] initWithFrame:NSZeroRect];
		field.bezeled = NO;
		field.bordered = NO;
		field.drawsBackground = NO;
		field.editable = NO;
		field.selectable = NO;
		field.usesSingleLineMode = NO;
		field.lineBreakMode = NSLineBreakByWordWrapping;
		field.cell.wraps = YES;
		field.cell.truncatesLastVisibleLine = NO;
		[field setWantsLayer:YES];
		[parentNSView addSubview:field];
		objc_setAssociatedObject(parentNSView, "gea.inline_field", field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	NSFont *parentFont = gea::macos::fontForId(node.style.font_id, node.style.font_size);
	NSColor *parentColor = gea::macos::rgb565ToNSColor(node.style.text_color);
	NSMutableAttributedString *composite = [[NSMutableAttributedString alloc] init];
	for (int c = node.first_child; c >= 0; c = tree.node(c).next_sibling) {
		appendInlineRuns(composite, c, parentFont, parentColor);
	}
	// Word-wrap paragraph style — same flow rules the rest of the renderer
	// uses, so the visual style stays consistent.
	NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
	ps.lineBreakMode = NSLineBreakByWordWrapping;
	[composite addAttribute:NSParagraphStyleAttributeName value:ps range:NSMakeRange(0, composite.length)];

	field.attributedStringValue = composite;
	// Fill the parent's content box. The framework already laid the parent
	// out wide enough for its children to flow, so AppKit's wrap point will
	// match that available width.
	field.frame = NSMakeRect(0, 0, parentNSView.bounds.size.width, parentNSView.bounds.size.height);
	field.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	// Mark every per-child view stale so the unseen-sweep removes them this
	// frame — composition replaces per-child rendering entirely.
	for (int c = node.first_child; c >= 0; c = tree.node(c).next_sibling) {
		(void)parentAbsX; (void)parentAbsY; (void)parentHeight;  // unused here
		[unseen addObject:@(c)];
	}
	return field;
}

void syncRecursive(int nodeId, NSView *parent, int parentAbsX, int parentAbsY, int parentHeight,
                   NSMutableSet<NSNumber *> *unseen)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	if (nodeId < 0 || nodeId >= tree.nodeCount()) return;
	const Node &node = tree.node(nodeId);

	NSNumber *key = @(nodeId);
	[unseen removeObject:key];

	NSView *view = ensureViewForNode(nodeId, node);
	if (view.superview != parent) {
		[view removeFromSuperview];
		[parent addSubview:view];
	}
	applyViewStyle(view, node, parentAbsX, parentAbsY, parentHeight);
	applyTypeSpecificProps(view, node, nodeId);

	// NSButton renders its own title from the Text child we read in
	// applyButtonProps; materializing the child as an NSTextField on top
	// would just be a redundant overlay. Skip descending into Buttons.
	if (node.type == NodeType::Button) return;

	// `<textarea>` owns its NSTextView as its only descendant — JSX children
	// (if any were authored) would otherwise be pushed inside NSTextView and
	// confuse text layout. The node's text content flows through the `value`
	// attribute, not via DOM children.
	if (isScrollView(view) && objc_getAssociatedObject(view, "gea.text_view")) return;

	// Inline composition path: parents like <p>{text}<span>...</span>{text}
	// render correctly only when AppKit gets the whole run as a single
	// attributed string. Detect that shape and short-circuit per-child
	// recursion in favour of one composite NSTextField on this view.
	if (node.type == NodeType::View && nodeIsInlineComposable(nodeId)) {
		renderInlineComposition(nodeId, view, parentAbsX, parentAbsY, parentHeight, unseen);
		return;
	}

	// Scrollable containers (VirtualList OR View with overflow:scroll) attach
	// children to the NSScrollView's documentView. parentHeight for those
	// children is the document's scrollable height so y-flip happens against
	// the full scroll content, not just the visible window. The children's
	// absolute coords use the node's own (layout.x, layout.y) because the
	// scroll document logically starts where the node starts.
	NSView *parentForChildren = view;
	int parentHeightForChildren = node.layout.height;
	int parentAbsXForChildren = node.layout.x;
	int parentAbsYForChildren = node.layout.y;
	if (isScrollView(view)) {
		NSScrollView *sv = (NSScrollView *)view;
		parentForChildren = sv.documentView ?: view;
		parentHeightForChildren = node.layout.scroll_content_height > 0
		                              ? node.layout.scroll_content_height
		                              : node.layout.height;
	}

	for (int child = node.first_child; child >= 0; child = tree.node(child).next_sibling) {
		syncRecursive(child, parentForChildren, parentAbsXForChildren, parentAbsYForChildren,
		              parentHeightForChildren, unseen);
	}
}

}  // namespace

MacosRenderer &MacosRenderer::instance()
{
	static MacosRenderer r;
	return r;
}

namespace {
// Install the centralized press/click handler on a root container once.
// Idempotent via an associated object so repeated sync passes don't stack
// recognizers.
void ensureRootClickBridge(NSView *parentForRoot)
{
	if (objc_getAssociatedObject(parentForRoot, "gea.root_click_bridge")) return;
	GeaRootClickBridge *bridge = [[GeaRootClickBridge alloc] init];
	bridge.rootView = parentForRoot;
	objc_setAssociatedObject(parentForRoot, "gea.root_click_bridge", bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	// NSPressGestureRecognizer (not NSClickGestureRecognizer) — we need the
	// began/ended state transitions so press-and-hold semantics work.
	// minimumPressDuration=0 fires began immediately on mouseDown.
	NSPressGestureRecognizer *gr =
	    [[NSPressGestureRecognizer alloc] initWithTarget:bridge action:@selector(fire:)];
	gr.minimumPressDuration = 0;
	gr.allowableMovement = 10000;  // don't cancel on drag — keep the press
	// The delegate declines clicks on editable text controls so they focus and
	// edit natively instead of being swallowed by this recognizer.
	gr.delegate = bridge;
	[parentForRoot addGestureRecognizer:gr];
}
}  // namespace

void MacosRenderer::sync(NSView *parentForRoot, int rootNodeId)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	if (rootNodeId < 0 || rootNodeId >= tree.nodeCount()) return;

	ensureRootClickBridge(parentForRoot);

	// Mark every existing entry stale; syncRecursive removes the keys it
	// touches. Anything still in the set after the walk corresponds to a
	// node that was removed from the tree (or moved out of the subtree
	// rooted at rootNodeId) — drop the NSView for it.
	NSMutableSet<NSNumber *> *unseen =
	    [NSMutableSet setWithArray:[nodeIdToView() allKeys]];

	const int parentHeight = static_cast<int>(parentForRoot.bounds.size.height);
	// Root's parent is the AppKit contentView. The root's own layout.x/y act
	// as document origin (0,0 for typical apps that fill the window), so we
	// pass (0, 0) as the parent-absolute-origin baseline.
	syncRecursive(rootNodeId, parentForRoot, 0, 0, parentHeight, unseen);

	for (NSNumber *gone in unseen) {
		NSView *v = nodeIdToView()[gone];
		[v removeFromSuperview];
		[nodeIdToView() removeObjectForKey:gone];
	}
}

void MacosRenderer::syncPanes(NSArray *paneViews, const int *rootNodeIds)
{
	using namespace gea::embedded::ui;
	Tree &tree = Tree::instance();
	const NSUInteger paneCount = paneViews.count;

	// One combined unseen set across ALL panes. If we instead called sync()
	// per pane, each call would sweep every map entry it didn't visit —
	// evicting the other panes' views. Build the stale set once, un-mark
	// across every pane walk, then sweep what's left.
	NSMutableSet<NSNumber *> *unseen =
	    [NSMutableSet setWithArray:[nodeIdToView() allKeys]];

	for (NSUInteger i = 0; i < paneCount; i++) {
		NSView *paneView = paneViews[i];
		const int rootNodeId = rootNodeIds[i];
		if (rootNodeId < 0 || rootNodeId >= tree.nodeCount()) continue;
		ensureRootClickBridge(paneView);
		const int parentHeight = static_cast<int>(paneView.bounds.size.height);
		// Each pane node's own layout.x/y act as its document origin, so the
		// pane's children land relative to the pane container's top-left.
		const Node &paneNode = tree.node(rootNodeId);
		syncRecursive(rootNodeId, paneView, paneNode.layout.x, paneNode.layout.y, parentHeight, unseen);
	}

	for (NSNumber *gone in unseen) {
		NSView *v = nodeIdToView()[gone];
		[v removeFromSuperview];
		[nodeIdToView() removeObjectForKey:gone];
	}
}

void MacosRenderer::teardown()
{
	for (NSView *v in [nodeIdToView() allValues]) {
		[v removeFromSuperview];
	}
	[nodeIdToView() removeAllObjects];
}

}  // namespace gea::macos

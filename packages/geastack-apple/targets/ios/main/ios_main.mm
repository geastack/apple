#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <TargetConditionals.h>

#if TARGET_OS_TV
#import <GameController/GameController.h>
#endif

#include "app.h"
#include "apps.h"
#include "canvas.h"
#include "css/animation.h"
#include "css/declarative.h"
#include "display.h"
#include "display_underlay.h"
#include "event.h"
#include "events.h"
#include "font_registry.h"
#include "image.h"
#include "ios_renderer.h"
#include "ios_root_background.h"
#include "pixel.h"
#include "ui/tree_internal.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#if __has_include("gea/apple/native_bridge.h")
#include "gea/apple/native_bridge.h"
#define GEA_IOS_HAS_APPLE_NATIVE_BRIDGE 1
#endif

extern "C" int gea_embedded_now_ms(void);
extern "C" void gea_ios_display_set_viewport_size(int width, int height);
extern "C" const std::uint32_t *gea_ios_display_presented_pixels();
extern "C" void gea_ios_touch_set_state(int touching, int x, int y);

@class GeaAppDelegate;
static __weak GeaAppDelegate *gGeaAppDelegate = nil;

// Wires the iOS AVFoundation camera backend (ios_camera.mm) to the runtime's
// board-independent <camera> preview seam. Defined in @geastack/host's host/camera.cpp.
namespace gea::framework::camera {
void registerCameraSurface();
}

namespace {

UIColor *rgb565ToUIColor(gea::framework::graphics::pixel::native_t color)
{
	// Style colours are native pixels (RGBA8888 on iOS) — unpack full 8-bit
	// channels so native UIKit views render true colour, not 565-quantized.
	int r, g, b, a;
	gea::framework::graphics::pixel::unpackNative8(color, &r, &g, &b, &a);
	return [UIColor colorWithRed:static_cast<CGFloat>(r) / 255.0
	                       green:static_cast<CGFloat>(g) / 255.0
	                        blue:static_cast<CGFloat>(b) / 255.0
	                       alpha:1.0];
}

NSString *NSStringFromAttr(const char *value)
{
	return [NSString stringWithUTF8String:value ? value : ""] ?: @"";
}

NSTextAlignment textAlignmentForStyle(int align)
{
	switch (align) {
	case 1: return NSTextAlignmentCenter;
	case 2: return NSTextAlignmentRight;
	default: return NSTextAlignmentLeft;
	}
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

NSMutableDictionary *textAttributes(UIFont *font, UIColor *color, int textDecoration)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	attrs[NSFontAttributeName] = font ?: [UIFont systemFontOfSize:16];
	attrs[NSForegroundColorAttributeName] = color ?: UIColor.blackColor;
	addTextDecorationAttributes(attrs, textDecoration);
	return attrs;
}

bool attributedStringHasTextDecoration(NSAttributedString *value)
{
	if (!value || value.length == 0) return false;
	return [value attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:nil] != nil ||
	       [value attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:nil] != nil;
}

}  // namespace

@interface GeaNativeInputField : UITextField <UITextFieldDelegate>
@property(nonatomic, assign) int nodeId;
@property(nonatomic, assign) BOOL syncingFromTree;
@property(nonatomic, assign) UIEdgeInsets textInsets;
@end

@implementation GeaNativeInputField

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_nodeId = -1;
		_syncingFromTree = NO;
		_textInsets = UIEdgeInsetsZero;
		self.delegate = self;
		self.borderStyle = UITextBorderStyleNone;
		self.backgroundColor = UIColor.clearColor;
		self.opaque = NO;
		self.autocorrectionType = UITextAutocorrectionTypeNo;
		self.autocapitalizationType = UITextAutocapitalizationTypeNone;
		self.spellCheckingType = UITextSpellCheckingTypeNo;
		self.returnKeyType = UIReturnKeyDone;
		if (@available(iOS 11.0, *)) {
			self.smartDashesType = UITextSmartDashesTypeNo;
			self.smartQuotesType = UITextSmartQuotesTypeNo;
			self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
		}
		[self addTarget:self action:@selector(editingChanged:) forControlEvents:UIControlEventEditingChanged];
	}
	return self;
}

- (CGRect)textRectForBounds:(CGRect)bounds
{
	return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
	return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds
{
	return UIEdgeInsetsInsetRect(bounds, self.textInsets);
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

- (void)editingChanged:(id)sender
{
	(void)sender;
	if (_syncingFromTree || _nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (_nodeId >= tree.nodeCount()) return;
	const char *utf8 = self.text ? [self.text UTF8String] : "";
	tree.setAttribute(_nodeId, "value", utf8 ? utf8 : "");
	[self dispatchEventOfType:gea::framework::events::PointerEventType::Input withKeyCode:0];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	(void)textField;
	if (_nodeId < 0) return;
	gea::embedded::ui::Tree::instance().setActiveInput(_nodeId);
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
	(void)textField;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (tree.activeInputId() == _nodeId) tree.setActiveInput(-1);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	(void)textField;
	[self dispatchEventOfType:gea::framework::events::PointerEventType::KeyDown withKeyCode:13];
	return YES;
}

- (void)deleteBackward
{
	[self dispatchEventOfType:gea::framework::events::PointerEventType::KeyDown withKeyCode:8];
	[super deleteBackward];
}

@end

#if TARGET_OS_TV
static void dispatchRemoteKey(int keyCode)
{
	auto &tree = gea::embedded::ui::Tree::instance();
	const int root = tree.mountedRoot();
	if (root < 0) return;

	gea::framework::events::PointerEvent event;
	event.targetId = tree.firstChildOf(root);
	if (event.targetId < 0) event.targetId = root;
	event.type = gea::framework::events::PointerEventType::KeyDown;
	event.keyCode = keyCode;
	const bool delivered = gea::embedded::ui::dispatchRootKeyEvent(event, true);
	if (std::getenv("GEA_TV_INPUT_DIAGNOSTICS"))
		NSLog(@"[Gea TV] key=%d root=%d target=%d delivered=%d", keyCode, root, event.targetId, delivered);
}

@interface GeaTVController : GCEventViewController
@property(nonatomic, weak) GCMotion *remoteMotion;
@property(nonatomic, assign) BOOL tiltReady;
@property(nonatomic, strong) NSHashTable<GCController *> *configuredControllers;
- (void)pollRemoteMotion;
@end

@implementation GeaTVController
- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self becomeFirstResponder];
}

- (void)pollRemoteMotion
{
	if (!self.configuredControllers) self.configuredControllers = [NSHashTable weakObjectsHashTable];
	for (GCController *controller in GCController.controllers) {
		if ([self.configuredControllers containsObject:controller]) continue;
		[self.configuredControllers addObject:controller];
		controller.handlerQueue = dispatch_get_main_queue();
		GCMicroGamepad *remote = controller.microGamepad;
		if (remote) remote.reportsAbsoluteDpadValues = YES;
		GCExtendedGamepad *pad = controller.extendedGamepad;
		const bool directionalRemote = [remote isKindOfClass:GCDirectionalGamepad.class];
		// The silver remote's generic dpad is its touch surface and buttonA
		// means a click anywhere, including the direction ring. Use the
		// dedicated physical ring and center elements to keep actions separate.
		GCControllerDirectionPad *directions = directionalRemote
		    ? remote.dpads[GCInputDirectionalCardinalDpad]
		    : (remote ? remote.dpad : pad.dpad);
		directions.left.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(37);
		};
		directions.right.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(39);
		};
		directions.up.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(38);
		};
		directions.down.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(40);
		};
		GCControllerButtonInput *select = directionalRemote
		    ? remote.buttons[GCInputDirectionalCenterButton]
		    : (remote ? remote.buttonA : pad.buttonA);
		select.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(13);
		};
		GCControllerButtonInput *back = remote ? remote.buttonMenu : pad.buttonMenu;
		back.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(27);
		};
		GCControllerButtonInput *dive = remote ? remote.buttonX : pad.buttonX;
		dive.pressedChangedHandler = ^(GCControllerButtonInput *, float, BOOL pressed) {
			if (pressed) dispatchRemoteKey(40);
		};
		if (std::getenv("GEA_TV_INPUT_DIAGNOSTICS"))
			NSLog(@"[Gea TV] controller=%@ profile=%@ motion=%d", controller.vendorName,
			      NSStringFromClass(remote ? remote.class : pad.class), controller.motion != nil);
	}
	GCMotion *motion = nil;
	for (GCController *controller in GCController.controllers) {
		if (!controller.motion) continue;
		motion = controller.motion;
		if (controller.microGamepad) break;
	}
	if (motion != self.remoteMotion) {
		GCMotion *previous = self.remoteMotion;
		if (previous.sensorsRequireManualActivation) previous.sensorsActive = NO;
		self.remoteMotion = motion;
		self.tiltReady = NO;
		if (motion.sensorsRequireManualActivation) motion.sensorsActive = YES;
	}
	if (!motion) return;
	if (motion.sensorsRequireManualActivation && !motion.sensorsActive) motion.sensorsActive = YES;

	// Hold the remote upright with its buttons facing you. Re-center before
	// the next lane change so a held tilt only generates one input.
	const double sideways = motion.hasGravityAndUserAcceleration ? motion.gravity.x : motion.acceleration.x;
	if (std::abs(sideways) < 0.16) self.tiltReady = YES;
	if (!self.tiltReady || std::abs(sideways) < 0.34) return;
	self.tiltReady = NO;
	dispatchRemoteKey(sideways < 0 ? 37 : 39);
}
@end
#endif

@interface GeaDisplayView : UIView
@property(nonatomic, strong) NSMapTable<UITouch *, NSNumber *> *touchPointerIds;
- (void)syncNativeTextInputs;
@end

@implementation GeaDisplayView

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		self.opaque = YES;
		self.backgroundColor = UIColor.blackColor;
		self.contentMode = UIViewContentModeRedraw;
		self.userInteractionEnabled = YES;
		// Track multiple simultaneous fingers so one button can be held while
		// another is tapped (e.g. move + jump). Keyed by touch identity; the
		// value is the pointer index (0 = primary).
#if !TARGET_OS_TV
		self.multipleTouchEnabled = YES;
#endif
		self.touchPointerIds = [NSMapTable mapTableWithKeyOptions:NSMapTableWeakMemory | NSMapTableObjectPointerPersonality
		                                             valueOptions:NSMapTableStrongMemory];
	}
	return self;
}

- (CGFloat)nativeContentScale
{
	CGFloat scale = self.contentScaleFactor;
	UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
	if (scale <= 0) scale = screen.nativeScale;
	if (scale <= 0) scale = screen.scale;
	return scale > 0 ? scale : 1;
}

- (CGPoint)nativePointForTouch:(UITouch *)touch
{
	return [self nativePointForViewPoint:[touch locationInView:self]];
}

- (CGPoint)nativePointForViewPoint:(CGPoint)point
{
	// Map view points into canvas/layout coordinates by the actual view->canvas
	// ratio. The canvas is sized in logical points, so this is ~1; for a
	// physical-pixel canvas it equals the content scale factor. Using the raw
	// content scale factor unconditionally assumed a physical-pixel canvas.
	auto *canvas = gea::platform::display::Display::canvas();
	const CGRect bounds = self.bounds;
	if (canvas && bounds.size.width > 0 && bounds.size.height > 0) {
		point.x *= static_cast<CGFloat>(canvas->width()) / bounds.size.width;
		point.y *= static_cast<CGFloat>(canvas->height()) / bounds.size.height;
	}
	return point;
}

- (int)clampedTouchX:(CGFloat)x
{
	int ix = static_cast<int>(std::lround(x));
	if (auto *canvas = gea::platform::display::Display::canvas()) {
		ix = std::clamp(ix, 0, std::max(0, canvas->width() - 1));
	}
	return std::max(0, ix);
}

- (int)clampedTouchY:(CGFloat)y
{
	int iy = static_cast<int>(std::lround(y));
	if (auto *canvas = gea::platform::display::Display::canvas()) {
		iy = std::clamp(iy, 0, std::max(0, canvas->height() - 1));
	}
	return std::max(0, iy);
}

- (CGRect)canvasDestinationRect
{
	auto *canvas = gea::platform::display::Display::canvas();
	if (!canvas || canvas->width() <= 0 || canvas->height() <= 0) return self.bounds;
	const CGRect bounds = self.bounds;
	const CGFloat scale = std::min(bounds.size.width / static_cast<CGFloat>(canvas->width()),
	                               bounds.size.height / static_cast<CGFloat>(canvas->height()));
	const CGSize size = CGSizeMake(static_cast<CGFloat>(canvas->width()) * scale,
	                               static_cast<CGFloat>(canvas->height()) * scale);
	return CGRectMake(bounds.origin.x + (bounds.size.width - size.width) * 0.5,
	                  bounds.origin.y + (bounds.size.height - size.height) * 0.5,
	                  size.width,
	                  size.height);
}

- (void)syncNativeTextInputs
{
	using namespace gea::embedded::ui;
	static NSMutableDictionary<NSNumber *, GeaNativeInputField *> *fields = nil;
	if (!fields) fields = [NSMutableDictionary new];

	auto *canvas = gea::platform::display::Display::canvas();
	if (!canvas || canvas->width() <= 0 || canvas->height() <= 0) {
		for (GeaNativeInputField *field in [fields allValues]) {
			[field resignFirstResponder];
			[field removeFromSuperview];
		}
		[fields removeAllObjects];
		return;
	}

	const CGRect dest = [self canvasDestinationRect];
	const CGFloat canvasScale = dest.size.width / static_cast<CGFloat>(canvas->width());
	auto &tree = Tree::instance();
	const int activeInput = tree.activeInputId();
	NSMutableSet<NSNumber *> *seen = [NSMutableSet set];

	for (int nodeId = 0; nodeId < tree.nodeCount(); nodeId++) {
		const Node &node = tree.node(nodeId);
		const char *tagName = tree.tagName(nodeId);
		if (node.type != NodeType::View || !tagName || std::strcmp(tagName, "input") != 0) continue;

		NSNumber *key = @(nodeId);
		[seen addObject:key];
		GeaNativeInputField *field = fields[key];
		if (!field) {
			field = [[GeaNativeInputField alloc] initWithFrame:CGRectZero];
			fields[key] = field;
			[self addSubview:field];
		} else if (field.superview != self) {
			[field removeFromSuperview];
			[self addSubview:field];
		}

		field.nodeId = nodeId;
		const CGFloat x = dest.origin.x + static_cast<CGFloat>(node.layout.x) * canvasScale;
		const CGFloat y = dest.origin.y + static_cast<CGFloat>(node.layout.y) * canvasScale;
		const CGFloat w = static_cast<CGFloat>(node.layout.width) * canvasScale;
		const CGFloat h = static_cast<CGFloat>(node.layout.height) * canvasScale;
		field.frame = CGRectMake(x, y, w, h);
		field.textInsets = UIEdgeInsetsMake(static_cast<CGFloat>(std::max<int>(0, node.style.padding[0])) * canvasScale,
		                                    static_cast<CGFloat>(std::max<int>(0, node.style.padding[3])) * canvasScale,
		                                    static_cast<CGFloat>(std::max<int>(0, node.style.padding[2])) * canvasScale,
		                                    static_cast<CGFloat>(std::max<int>(0, node.style.padding[1])) * canvasScale);
		field.hidden = (node.style.display == 1 || node.style.opacity == 0 || w <= 0 || h <= 0);
		field.userInteractionEnabled = !field.hidden;
		field.alpha = static_cast<CGFloat>(node.style.opacity) / 255.0;
		field.backgroundColor = node.style.has_bg ? rgb565ToUIColor(node.style.bg_color) : UIColor.clearColor;
		field.layer.borderWidth = static_cast<CGFloat>(std::max<int>(0, node.style.border_width)) * canvasScale;
		field.layer.borderColor = rgb565ToUIColor(node.style.border_color).CGColor;
		const int tl = std::max<int>(0, node.style.border_radius[0]);
		const int tr = std::max<int>(0, node.style.border_radius[1]);
		const int br = std::max<int>(0, node.style.border_radius[2]);
		const int bl = std::max<int>(0, node.style.border_radius[3]);
		const CGFloat radius = (tl == tr && tr == br && br == bl)
		                           ? static_cast<CGFloat>(tl)
		                           : static_cast<CGFloat>(tl + tr + br + bl) / 4.0;
		field.layer.cornerRadius = radius * canvasScale;
		field.layer.masksToBounds = field.layer.cornerRadius > 0;
		const CGFloat fontSize = std::max<CGFloat>(1.0, static_cast<CGFloat>(node.style.font_size > 0 ? node.style.font_size : 16) * canvasScale);
		field.textColor = rgb565ToUIColor(node.style.text_color);
		field.font = gea::ios::fontForId(node.style.font_id, fontSize);
		field.textAlignment = textAlignmentForStyle(node.style.text_align);
		NSMutableDictionary *textAttrs = textAttributes(field.font, field.textColor, node.style.text_decoration);
		field.defaultTextAttributes = textAttrs;

		const char *typeAttr = tree.getAttribute(nodeId, "type");
		NSString *type = [NSStringFromAttr(typeAttr) lowercaseString];
		field.secureTextEntry = [type isEqualToString:@"password"];
		if ([type isEqualToString:@"email"]) field.keyboardType = UIKeyboardTypeEmailAddress;
		else if ([type isEqualToString:@"number"]) field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
		else if ([type isEqualToString:@"tel"]) field.keyboardType = UIKeyboardTypePhonePad;
		else if ([type isEqualToString:@"url"]) field.keyboardType = UIKeyboardTypeURL;
		else field.keyboardType = UIKeyboardTypeDefault;

		NSString *placeholder = NSStringFromAttr(tree.getAttribute(nodeId, "placeholder"));
		field.placeholder = placeholder.length > 0 ? placeholder : nil;

		NSString *desiredValue = NSStringFromAttr(tree.getAttribute(nodeId, "value"));
		const BOOL textDiffers = ![(field.text ?: @"") isEqualToString:desiredValue];
		const BOOL usesDecoratedText = node.style.text_decoration != 0;
		if (textDiffers) {
			field.syncingFromTree = YES;
			if (usesDecoratedText) {
				field.attributedText = [[NSAttributedString alloc] initWithString:desiredValue attributes:textAttrs];
			} else {
				field.text = desiredValue;
			}
			field.syncingFromTree = NO;
		} else if (!field.isFirstResponder) {
			if (usesDecoratedText) {
				NSAttributedString *decoratedValue = [[NSAttributedString alloc] initWithString:desiredValue attributes:textAttrs];
				if (![field.attributedText isEqualToAttributedString:decoratedValue]) {
					field.syncingFromTree = YES;
					field.attributedText = decoratedValue;
					field.syncingFromTree = NO;
				}
			} else if (attributedStringHasTextDecoration(field.attributedText)) {
				field.syncingFromTree = YES;
				field.text = desiredValue;
				field.syncingFromTree = NO;
			}
		}

		if (activeInput == nodeId && !field.hidden) {
			if (!field.isFirstResponder) [field becomeFirstResponder];
		} else if (field.isFirstResponder) {
			[field resignFirstResponder];
		}
		if (!field.hidden) [self bringSubviewToFront:field];
	}

	for (NSNumber *key in [fields allKeys]) {
		if ([seen containsObject:key]) continue;
		GeaNativeInputField *field = fields[key];
		[field resignFirstResponder];
		[field removeFromSuperview];
		[fields removeObjectForKey:key];
	}
}

- (int)pointerIdForTouch:(UITouch *)touch assignIfAbsent:(BOOL)assign
{
	NSNumber *existing = [self.touchPointerIds objectForKey:touch];
	if (existing) return existing.intValue;
	if (!assign) return -1;
	// Reuse the lowest free pointer index so ids stay small and stable.
	unsigned int used = 0;
	for (NSNumber *value in [[self.touchPointerIds objectEnumerator] allObjects]) {
		const int v = value.intValue;
		if (v >= 0 && v < 31) used |= (1u << v);
	}
	int pointerId = 0;
	while (pointerId < 31 && (used & (1u << pointerId))) pointerId++;
	[self.touchPointerIds setObject:@(pointerId) forKey:touch];
	return pointerId;
}

- (void)dispatchTouchPhase:(gea::framework::events::TouchPhase)phase
                  touching:(bool)touching
                   nativeX:(int)x
                   nativeY:(int)y
                 pointerId:(int)pointerId
{
	// Only the primary pointer (0) drives the single-point hardware touch state
	// that polling apps read; every finger dispatches DOM-style touch events.
	if (pointerId == 0) gea_ios_touch_set_state(touching ? 1 : 0, x, y);
	gea::framework::events::Event event{};
	event.type = gea::framework::events::EventType::Touch;
	event.touchPhase = phase;
	event.touching = touching;
	event.x = x;
	event.y = y;
	event.pointerId = pointerId;
	gea::framework::events::TouchRuntime::dispatchEvent(event);
}

- (void)dispatchTouch:(UITouch *)touch
                phase:(gea::framework::events::TouchPhase)phase
             touching:(bool)touching
{
	if (!touch) return;
#if TARGET_OS_TV
	// Remote touch coordinates describe the clickpad, not positions on the TV.
	// GameController owns that input; forwarding it as pointer gestures sends
	// a second, unrelated action whenever a thumb touches or moves on the pad.
	if (touch.type == UITouchTypeIndirect) return;
#endif
	const BOOL isDown = phase == gea::framework::events::TouchPhase::Down;
	const int pointerId = [self pointerIdForTouch:touch assignIfAbsent:isDown];
	if (pointerId < 0) return;
	const CGPoint point = [self nativePointForTouch:touch];
	const int x = [self clampedTouchX:point.x];
	const int y = [self clampedTouchY:point.y];
	[self dispatchTouchPhase:phase touching:touching nativeX:x nativeY:y pointerId:pointerId];
	if (phase == gea::framework::events::TouchPhase::Up) {
		[self.touchPointerIds removeObjectForKey:touch];
	}
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	(void)event;
	for (UITouch *touch in touches) {
		[self dispatchTouch:touch phase:gea::framework::events::TouchPhase::Down touching:true];
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	(void)event;
	for (UITouch *touch in touches) {
		[self dispatchTouch:touch phase:gea::framework::events::TouchPhase::Move touching:true];
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	(void)event;
	for (UITouch *touch in touches) {
		[self dispatchTouch:touch phase:gea::framework::events::TouchPhase::Up touching:false];
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	(void)event;
	for (UITouch *touch in touches) {
		[self dispatchTouch:touch phase:gea::framework::events::TouchPhase::Up touching:false];
	}
}

- (void)drawRect:(CGRect)dirtyRect
{
	(void)dirtyRect;
	if (gea::ios::IosRenderer::instance().hasNativeTree()) return;
	auto *canvas = gea::platform::display::Display::canvas();
	if (!canvas) return;
	const std::uint32_t *src = gea_ios_display_presented_pixels();
	const int w = canvas->width();
	const int h = canvas->height();
	if (!src || w <= 0 || h <= 0) return;

	// The framebuffer is already RGBA8888 (bytes R,G,B,A per pixel) — copy it
	// straight into the CGImage scratch; no RGB565 expansion needed.
	static std::uint8_t *scratch = nullptr;
	static std::size_t scratchBytes = 0;
	const std::size_t bytes = static_cast<std::size_t>(w) * h * 4;
	if (scratchBytes < bytes) {
		void *grown = std::realloc(scratch, bytes);
		if (!grown) return;
		scratch = static_cast<std::uint8_t *>(grown);
		scratchBytes = bytes;
	}
	std::memcpy(scratch, src, bytes);

	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, scratch, bytes, nullptr);
	const uint32_t bitmapInfo = static_cast<uint32_t>(kCGImageAlphaNoneSkipLast) |
	                            static_cast<uint32_t>(kCGBitmapByteOrder32Big);
	CGImageRef image = CGImageCreate(static_cast<std::size_t>(w), static_cast<std::size_t>(h),
	                                 8, 32, static_cast<std::size_t>(w) * 4,
	                                 cs, bitmapInfo, provider, nullptr, false,
	                                 kCGRenderingIntentDefault);

	const CGRect bounds = self.bounds;
	const CGFloat scale = std::min(bounds.size.width / static_cast<CGFloat>(w),
	                               bounds.size.height / static_cast<CGFloat>(h));
	const CGSize size = CGSizeMake(static_cast<CGFloat>(w) * scale,
	                               static_cast<CGFloat>(h) * scale);
	const CGRect dest = CGRectMake(bounds.origin.x + (bounds.size.width - size.width) * 0.5,
	                               bounds.origin.y + (bounds.size.height - size.height) * 0.5,
	                               size.width,
	                               size.height);
	UIImage *renderedImage = [UIImage imageWithCGImage:image];
	[renderedImage drawInRect:dest];

	CGImageRelease(image);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(cs);
}

@end

@interface GeaAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIView *rootView;
@property(nonatomic, strong) GeaDisplayView *displayView;
@property(nonatomic, strong) UIView *nativeRootView;
@property(nonatomic, strong) CADisplayLink *displayLink;
- (void)installNativeRootView:(UIView *)view;
@end

@implementation GeaAppDelegate

- (void)layoutDisplayViewInSafeArea
{
	if (!self.rootView || !self.displayView) return;
#if TARGET_OS_TV
	CGRect frame = self.rootView.bounds;
#else
	CGRect frame = self.rootView.safeAreaLayoutGuide.layoutFrame;
	if (frame.size.width <= 0 || frame.size.height <= 0) {
		frame = UIEdgeInsetsInsetRect(self.rootView.bounds, self.rootView.safeAreaInsets);
	}
	if (frame.size.width <= 0 || frame.size.height <= 0) frame = self.rootView.bounds;
#endif
	self.displayView.frame = frame;
	if (self.nativeRootView) self.nativeRootView.frame = self.rootView.bounds;
}

- (void)installNativeRootView:(UIView *)view
{
	if (!view || !self.rootView) return;
	if (self.nativeRootView && self.nativeRootView.superview == self.rootView) {
		[self.nativeRootView removeFromSuperview];
	}
	self.nativeRootView = view;
	view.frame = self.rootView.bounds;
	view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	view.hidden = NO;
	view.userInteractionEnabled = YES;
	self.displayView.hidden = YES;
	self.displayView.userInteractionEnabled = NO;
	[self.rootView addSubview:view];
	[view setNeedsLayout];
}

- (CGSize)viewportSize
{
	CGSize size = self.displayView.bounds.size;
	if (size.width <= 0 || size.height <= 0) size = self.rootView.safeAreaLayoutGuide.layoutFrame.size;
	if (size.width <= 0 || size.height <= 0) size = self.rootView.bounds.size;
	if (size.width <= 0 || size.height <= 0) size = self.window.bounds.size;
	if (size.width <= 0 || size.height <= 0) size = UIScreen.mainScreen.bounds.size;
	return size;
}

- (CGFloat)viewportScale
{
	UIScreen *screen = self.displayView.window.screen ?: self.window.screen ?: UIScreen.mainScreen;
	CGFloat scale = screen.nativeScale;
	if (scale <= 0) scale = screen.scale;
	if (scale <= 0) scale = self.displayView.contentScaleFactor;
	return scale > 0 ? scale : 1;
}

- (void)syncAppBackgroundColor
{
	gea::framework::graphics::pixel::native_t rootColor = 0;
	UIColor *color = gea::ios::mountedRootBackgroundColor(&rootColor) ? rgb565ToUIColor(rootColor) : UIColor.blackColor;
	self.window.backgroundColor = color;
	self.rootView.backgroundColor = color;
	self.displayView.backgroundColor = color;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	(void)application;
	(void)launchOptions;
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	#if TARGET_OS_TV
	GeaTVController *controller = [[GeaTVController alloc] init];
	controller.controllerUserInteractionEnabled = NO;
	application.idleTimerDisabled = YES;
#else
	UIViewController *controller = [[UIViewController alloc] init];
#endif
	self.rootView = [[UIView alloc] initWithFrame:self.window.bounds];
	self.rootView.opaque = YES;
	self.rootView.backgroundColor = UIColor.blackColor;
	self.rootView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.displayView = [[GeaDisplayView alloc] initWithFrame:CGRectZero];
	self.displayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.rootView addSubview:self.displayView];
	controller.view = self.rootView;
	self.window.rootViewController = controller;
	[self.window makeKeyAndVisible];
#if TARGET_OS_TV
	[controller becomeFirstResponder];
#endif
	[self.rootView layoutIfNeeded];
	[self layoutDisplayViewInSafeArea];
	gGeaAppDelegate = self;

	CGSize viewport = [self viewportSize];
	const CGFloat viewportScale = [self viewportScale];
	self.displayView.contentScaleFactor = viewportScale;
	// Viewport/layout space is LOGICAL CSS px (points), NOT physical pixels.
	// Multiplying by viewportScale here made window.innerWidth/innerHeight report
	// physical pixels, so fixed-px app layouts (e.g. Sky Hop's 36px tiles)
	// rendered ~3x too dense on retina. UIKit renders the native view tree
	// crisply at the screen's content scale factor (set above) independently, so
	// gea's internal CSS device-pixel-ratio stays 1 — otherwise `px` lengths get
	// an extra x scale (cssPixelLength) that unitless lengths don't, blowing up
	// fonts (16px/36px) relative to the unitless tile layout.
	const int viewportWidth = std::max(1, static_cast<int>(std::ceil(viewport.width)));
	const int viewportHeight = std::max(1, static_cast<int>(std::ceil(viewport.height)));
	const int devicePixelRatio = 1;
	gea_ios_display_set_viewport_size(viewportWidth, viewportHeight);
	gea::platform::display::Display::init();
	gea::framework::camera::registerCameraSurface();
	// On iOS the build sets GEA_EMBEDDED_PIXEL_FORMAT=GEA_PIXEL_RGBA8888, so the
	// ImageStore decodes straight to full-colour RGBA8888 native pixels (no 565
	// quantization, no separate retained buffer) for native UIImageView.
	gea::framework::app::Application::init(viewportWidth, viewportHeight, devicePixelRatio);
	[self syncAppBackgroundColor];
	[self tick:nil];

	self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
	if (@available(iOS 15.0, *)) {
		self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
	} else {
		self.displayLink.preferredFramesPerSecond = 60;
	}
	[self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
	return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	(void)application;
	self.displayLink.paused = YES;
#if TARGET_OS_TV
	GCMotion *motion = ((GeaTVController *)self.window.rootViewController).remoteMotion;
	if (motion.sensorsRequireManualActivation) motion.sensorsActive = NO;
#endif
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
#if TARGET_OS_TV
	application.idleTimerDisabled = NO;
#else
	(void)application;
#endif
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
#if TARGET_OS_TV
	application.idleTimerDisabled = YES;
	[self.window.rootViewController becomeFirstResponder];
#else
	(void)application;
#endif
	self.displayLink.paused = NO;
}

- (void)tick:(CADisplayLink *)link
{
#if TARGET_OS_TV
	[(GeaTVController *)self.window.rootViewController pollRemoteMotion];
#endif
	(void)link;
	const int nowMs = gea_embedded_now_ms();
	// This host replaces runtime.cpp's frame loop, including its animation
	// clock. Prime newly mounted CSS tracks and advance them before rendering.
	static bool declarativeAnimationsScanned = false;
	if (!declarativeAnimationsScanned) {
		declarativeAnimationsScanned = true;
		gea::css::DeclarativeAnimations::scanAndStart(nowMs);
	}
	gea::embedded::ui::StyleSheet::instance().startCssAnimations(static_cast<std::uint32_t>(nowMs));
	gea::css::AnimationEngine::instance().tick(static_cast<std::uint32_t>(nowMs));
	gea::framework::app::Application::frame(nowMs);
	[self syncAppBackgroundColor];
	auto &tree = gea::embedded::ui::Tree::instance();
	const int root = tree.mountedRoot();
	if (!self.nativeRootView) {
		auto &renderer = gea::ios::IosRenderer::instance();
		if (root < 0 || gea::framework::display::Underlay::active()) {
			// Direct-canvas apps and composited underlays present the framework
			// framebuffer. Remove native views that would cover that image.
			if (renderer.hasNativeTree()) renderer.teardown();
		} else {
			renderer.sync(self.displayView, root);
			[self.displayView syncNativeTextInputs];
		}
		[self.displayView setNeedsDisplay];
	}
}

@end

#if GEA_IOS_HAS_APPLE_NATIVE_BRIDGE
void gea::apple::UIKit::installRootView(gea::apple::UIKit::UIView view)
{
	::UIView *nativeView = (__bridge ::UIView *)gea::apple::objc::object(view.handle);
	if (!nativeView) return;
	if ([NSThread isMainThread]) {
		[gGeaAppDelegate installNativeRootView:nativeView];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[gGeaAppDelegate installNativeRootView:nativeView];
	});
}
#endif

// The on-screen UIView hosting the gea framebuffer. The camera backend
// (ios_camera.mm) attaches its AVCaptureVideoPreviewLayer to this view's layer
// and positions it to a <camera> node's computed rect (NativeOverlay preview).
extern "C" UIView *gea_ios_camera_host_view(void)
{
	return gGeaAppDelegate.displayView;
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([GeaAppDelegate class]));
	}
}

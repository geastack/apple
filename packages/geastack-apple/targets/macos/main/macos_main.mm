#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#import <QuartzCore/CADisplayLink.h>

#if defined(GEA_NATIVE_DEBUGGER) && GEA_NATIVE_DEBUGGER
extern void gea_macos_debugger_start();
#endif

#include "font_registry.h"
#include "macos_native_shell.h"
#include "macos_renderer.h"
#include "press_bridge.h"
#include "thermalright_hid_display.h"

namespace gea::macos { void installAppLauncherPlatform(const char *currentAppId); }
namespace gea::macos { void installWifiDriver(); int nodeIdForView(NSView *view); }

#include "app.h"
#include "css/declarative.h"
#include "css/engine.h"
#include "display.h"
#include "platform/file_cache.h"
#if __has_include("resident_apps.h")
#include "resident_apps.h"
#define GEA_MACOS_HAS_RESIDENT_APPS 1
#else
#define GEA_MACOS_HAS_RESIDENT_APPS 0
#endif
#include "ui/document.h"
#include "ui/node.h"
#include "ui/node_model.h"
#include "ui/style.h"
#include "ui/tree_internal.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" int gea_embedded_now_ms(void);
// Headless text-input driver used by GEA_MACOS_SYNTH_INPUT (press_bridge.mm).
extern "C" int gea_macos_fire_input_for_node(int nodeId, const char *text);

static void gea_macos_smoke_log(const char *message)
{
	const char *path = std::getenv("GEA_MACOS_MAIN_SMOKE_LOG");
	if (!path || path[0] == '\0') return;
	if (FILE *file = std::fopen(path, "a")) {
		std::fprintf(file, "%s\n", message);
		std::fclose(file);
	}
}

// Apple-native apps (those importing @geajs/apple/*) make geatsc emit this
// handle-table bridge header plus Objective-C++ app modules. When present, this
// file is built in apple-native mode: __gea_top_level (run from Application::init)
// builds a real AppKit object graph and calls AppKit::installRootView, which we
// implement at the bottom of this file to swap the window's content view.
#if __has_include("gea/apple/native_bridge.h")
#include "gea/apple/native_bridge.h"
#define GEA_MACOS_HAS_APPLE_NATIVE_BRIDGE 1
#endif

// App-owned controls consume ordinary Gea events. AppKit supplies only the
// window and text services, including keyboard layout and IME composition.
static int geaCustomInputRoot()
{
 auto &tree = gea::embedded::ui::Tree::instance();
 for (int i=0;i<tree.nodeCount();++i)
  if (std::strcmp(tree.getAttribute(i,"data-gea-inputs"),"true")==0) return i;
 return -1;
}
// Authored silhouettes own their press layer; a rectangular engine fill would
// paint outside their transparent corners. Ancestors cover image/text hits.
static bool geaOwnsContourPress(int x, int y) {
 auto &tree=gea::embedded::ui::Tree::instance();
 for (int id=tree.hitTestNode(x,y);id>=0;id=tree.node(id).parent)
  if (std::strcmp(tree.getAttribute(id,"data-gea-contour"),"true")==0) return true;
 return false;
}
@interface GeaContentView : NSView <NSTextInputClient>
@property(nonatomic,copy) NSAttributedString *geaMarkedText;
@property(nonatomic,strong) GCController *geaActiveController;
@property(nonatomic) unsigned int geaGamepadButtons;
@property(nonatomic) NSTimeInterval geaGamepadRepeat;
@property(nonatomic,strong) id geaCursorMonitor;
@property(nonatomic,strong) NSTrackingArea *geaPointerTracking;
@end
@implementation GeaContentView
// Optional app cursor is scoped to the content bounds; AppKit restores the
// standard pointer over the title bar, other windows, and other applications.
- (void)resetCursorRects {
 [super resetCursorRects];
 static NSCursor *cursor = nil;
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"window.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  NSDictionary *config = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![config isKindOfClass:[NSDictionary class]]) return;
  NSDictionary *window = config[@"window"] ?: config;
  NSDictionary *spec = window[@"cursor"];
  if (![spec isKindOfClass:[NSDictionary class]] || ![spec[@"style"] isEqual:@"angular"]) return;
  CGFloat size = [spec[@"size"] respondsToSelector:@selector(doubleValue)] ? [spec[@"size"] doubleValue] : 28;
  size = std::clamp((double)size, 20.0, 48.0);
  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size + 6)];
  [image lockFocus];
  NSAffineTransform *transform = [NSAffineTransform transform];
  [transform translateXBy:0 yBy:size + 6];
  [transform scaleXBy:size / 28 yBy:-size / 28];
  [transform concat];
  NSBezierPath *arrow = [NSBezierPath bezierPath];
  [arrow moveToPoint:NSMakePoint(2,2)];
  [arrow lineToPoint:NSMakePoint(23,18)];
  [arrow lineToPoint:NSMakePoint(12,21)];
  [arrow lineToPoint:NSMakePoint(3,29)];
  [arrow closePath];
  [[NSColor colorWithCalibratedRed:0.04 green:0.12 blue:0.16 alpha:1] setFill];
  [arrow fill];
  [[NSColor colorWithCalibratedRed:0.69 green:0.93 blue:0.94 alpha:1] setStroke];
  arrow.lineWidth = 1.6; [arrow stroke];
  NSBezierPath *accent = [NSBezierPath bezierPath];
  [accent moveToPoint:NSMakePoint(5,8)]; [accent lineToPoint:NSMakePoint(16,16)];
  [[NSColor whiteColor] setStroke]; accent.lineWidth = 1; [accent stroke];
  [image unlockFocus];
  cursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(2 * size / 28, 2 * size / 28)];
 });
 if (cursor) {
  [self addCursorRect:self.bounds cursor:cursor];
  if (!self.geaCursorMonitor) {
   __weak GeaContentView *weakView = self;
   NSMutableArray<NSCursor *> *frames = [NSMutableArray array];
   for (int i=0;i<16;i++) {
    const double t=i/15.0;
    const double scale=1.0-0.17*std::sin(M_PI*t);
    NSSize size=cursor.image.size;
    NSImage *frame=[[NSImage alloc] initWithSize:size];
    [frame lockFocus];
    const NSPoint hotspot=cursor.hotSpot;
    [cursor.image drawInRect:NSMakeRect(hotspot.x*(1-scale),(size.height-hotspot.y)*(1-scale),size.width*scale,size.height*scale) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [frame unlockFocus];
    [frames addObject:[[NSCursor alloc] initWithImage:frame hotSpot:hotspot]];
   }
   self.geaCursorMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp) handler:^NSEvent *(NSEvent *event) {
    GeaContentView *view=weakView;
    if (!view || event.window!=view.window) return event;
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    auto &tree=gea::embedded::ui::Tree::instance();
    const bool inside=NSPointInRect(point,view.bounds);
    const int x=std::lround(point.x), y=std::lround(view.bounds.size.height-point.y);
    if (!std::getenv("GEA_MACOS_REPLAY_PLAN") && geaCustomInputRoot()>=0) {
     tree.pointerHover(inside?x:-1,inside?y:-1);
     if (event.type==NSEventTypeLeftMouseDown && inside && !geaOwnsContourPress(x,y)) tree.pointerDown(x,y);
     if (event.type==NSEventTypeLeftMouseUp) { tree.pointerUp(); gea::embedded::ui::StyleSheet::instance().hoverChanged(); }
    }
    if (!inside || event.type!=NSEventTypeLeftMouseDown) return event;
    // Gesture recognizers can consume the up event; never leave a press latched.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
     if (!(NSEvent.pressedMouseButtons & 1)) {
      gea::embedded::ui::Tree::instance().pointerUp();
      gea::embedded::ui::StyleSheet::instance().hoverChanged();
     }
    });
    for (int i=0;i<16;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*0.008*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
     GeaContentView *current=weakView;
     if (current.window.isKeyWindow && NSApp.isActive && NSPointInRect([current convertPoint:current.window.mouseLocationOutsideOfEventStream fromView:nil],current.bounds)) [frames[i] set];
    });
    return event;
   }];
  }
 }
}
- (void)updateTrackingAreas {
 [super updateTrackingAreas];
 if (self.geaPointerTracking) [self removeTrackingArea:self.geaPointerTracking];
 self.geaPointerTracking=[[NSTrackingArea alloc] initWithRect:NSZeroRect options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect) owner:self userInfo:nil];
 [self addTrackingArea:self.geaPointerTracking];
}
- (void)mouseExited:(NSEvent *)event {
 if (geaCustomInputRoot()>=0 && !std::getenv("GEA_MACOS_REPLAY_PLAN")) gea::embedded::ui::Tree::instance().pointerHover(-1,-1);
 [super mouseExited:event];
}
- (void)dealloc {
 if (self.geaCursorMonitor) [NSEvent removeMonitor:self.geaCursorMonitor];
}
- (void)geaPollGamepad {
 if (!NSApp.isActive || !self.window.isKeyWindow || geaCustomInputRoot()<0) {
  self.geaGamepadButtons=0; self.geaGamepadRepeat=0; return;
 }
 GCController *controller=nil;
 for (GCController *candidate in GCController.controllers) if (candidate.extendedGamepad) { controller=candidate; break; }
 if (controller!=self.geaActiveController) { self.geaActiveController=controller; self.geaGamepadButtons=0; self.geaGamepadRepeat=0; }
 GCExtendedGamepad *pad=controller.extendedGamepad;
 if (!pad) { self.geaGamepadButtons=0; return; }
 // Axis dead zone, edge-triggered face buttons, delayed directional repeat.
 const bool buttons[]={pad.dpad.up.isPressed || pad.leftThumbstick.yAxis.value>0.55f,
  pad.dpad.down.isPressed || pad.leftThumbstick.yAxis.value < -0.55f,
  pad.dpad.left.isPressed || pad.leftThumbstick.xAxis.value < -0.55f,
  pad.dpad.right.isPressed || pad.leftThumbstick.xAxis.value>0.55f,
  pad.buttonA.isPressed,pad.buttonB.isPressed,pad.buttonY.isPressed,pad.buttonX.isPressed,
  pad.leftShoulder.isPressed,pad.rightShoulder.isPressed,pad.leftTrigger.isPressed,pad.rightTrigger.isPressed,
  pad.leftThumbstickButton.isPressed,pad.rightThumbstickButton.isPressed,pad.buttonMenu.isPressed};
 unsigned int current=0; for(int i=0;i<15;i++) if(buttons[i])current|=1u<<i;
 unsigned int pressed=current & ~self.geaGamepadButtons;
 const NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
 const unsigned int directions=current & 15;
 if(pressed & 15) self.geaGamepadRepeat=now+0.38;
 else if(directions && now>=self.geaGamepadRepeat) { pressed|=directions; self.geaGamepadRepeat=now+0.12; }
 self.geaGamepadButtons=current;
 for(int i=0;i<15;i++) if(pressed & (1u<<i)) [self geaSendKey:2000+i];
}
- (BOOL)isFlipped { return NO; }
- (BOOL)acceptsFirstResponder { return geaCustomInputRoot()>=0; }
- (void)geaSendKey:(int)code {
 const int root=geaCustomInputRoot();if(root<0)return;
 gea::framework::events::PointerEvent event;
 event.type=gea::framework::events::PointerEventType::KeyDown;
 event.targetId=root;event.keyCode=code;
 if(!gea::embedded::ui::dispatchDocumentKeyDown(event)) gea::embedded::ui::Tree::instance().dispatchEvent(event);
}
- (void)keyDown:(NSEvent *)event {
 if(geaCustomInputRoot()<0){[super keyDown:event];return;}
 if((event.modifierFlags & NSEventModifierFlagCommand) && [[event.charactersIgnoringModifiers lowercaseString] isEqualToString:@"a"]){[self geaSendKey:1001];return;}
 if([event.charactersIgnoringModifiers isEqualToString:@" "]){[self geaSendKey:32];if(![self hasMarkedText])[self insertText:@" " replacementRange:NSMakeRange(NSNotFound,0)];return;}
 [self interpretKeyEvents:@[event]];
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
 (void)range;const int root=geaCustomInputRoot();if(root<0)return;
 NSString *value=[text isKindOfClass:[NSAttributedString class]]?[text string]:text;
 auto &tree=gea::embedded::ui::Tree::instance();
 tree.setAttribute(root,"value",value.UTF8String?:"");
 gea::framework::events::PointerEvent event;event.type=gea::framework::events::PointerEventType::Input;event.targetId=root;tree.dispatchEvent(event);
 self.geaMarkedText=nil;
}
- (void)doCommandBySelector:(SEL)selector {
 int code=0;
 if(selector==@selector(deleteBackward:))code=8;
 else if(selector==@selector(deleteForward:))code=46;
 else if(selector==@selector(moveLeft:))code=37;
 else if(selector==@selector(moveRight:))code=39;
 else if(selector==@selector(moveUp:))code=38;
 else if(selector==@selector(moveDown:))code=40;
 else if(selector==@selector(moveToBeginningOfLine:))code=36;
 else if(selector==@selector(moveToEndOfLine:))code=35;
 else if(selector==@selector(insertNewline:))code=13;
 else if(selector==@selector(insertTab:))code=9;
 else if(selector==@selector(cancelOperation:))code=27;
 if(code)[self geaSendKey:code];
}
- (void)paste:(id)sender { (void)sender;NSString *value=[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];if(value)[self insertText:value replacementRange:NSMakeRange(NSNotFound,0)]; }
- (void)copy:(id)sender {
 (void)sender;const int root=geaCustomInputRoot();if(root<0)return;
 NSString *text=[NSString stringWithUTF8String:gea::embedded::ui::Tree::instance().getAttribute(root,"data-gea-selected-text")];
 if(text.length){NSPasteboard *board=[NSPasteboard generalPasteboard];[board clearContents];[board setString:text forType:NSPasteboardTypeString];}
}
- (void)cut:(id)sender { [self copy:sender];[self geaSendKey:46]; }
- (void)selectAll:(id)sender { (void)sender;[self geaSendKey:1001]; }
- (BOOL)hasMarkedText { return self.geaMarkedText.length>0; }
- (NSRange)markedRange { return [self hasMarkedText]?NSMakeRange(0,self.geaMarkedText.length):NSMakeRange(NSNotFound,0); }
- (NSRange)selectedRange { return NSMakeRange(NSNotFound,0); }
- (void)setMarkedText:(id)text selectedRange:(NSRange)selection replacementRange:(NSRange)replacement {
 (void)selection;(void)replacement;self.geaMarkedText=[text isKindOfClass:[NSAttributedString class]]?text:[[NSAttributedString alloc] initWithString:text];
}
- (void)unmarkText { self.geaMarkedText=nil; }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual { (void)range;if(actual)*actual=NSMakeRange(NSNotFound,0);return nil; }
- (NSUInteger)characterIndexForPoint:(NSPoint)point { (void)point;return NSNotFound; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual {
 (void)range;if(actual)*actual=NSMakeRange(NSNotFound,0);return [self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) GeaContentView *rootView;
@property(nonatomic, strong) NSTimer *frameTimer;
@property(nonatomic, strong) CADisplayLink *frameDisplayLink API_AVAILABLE(macos(14.0));
@property(nonatomic, strong) GeaSplitShell *splitShell;
@property(nonatomic, strong) id geaToolbarDelegate; // NSToolbar.delegate is weak; retain it here
@property(nonatomic, assign) BOOL geaDidFinishBoot;
@property(nonatomic, assign) double geaProfileApplicationMs;
- (void)installNativeRootView:(NSView *)view;
- (void)startFrameTimer;
- (void)updateDisplayLinkRate API_AVAILABLE(macos(14.0));
@end

// Set once the delegate exists so the apple-native AppKit::installRootView entry
// (called from inside Application::init → __gea_top_level) can reach the window.
static __weak AppDelegate *gGeaAppDelegate = nil;

@implementation AppDelegate

- (void)installMainMenu
{
	NSMenu *mainMenu = [[NSMenu alloc] init];

	NSMenuItem *appItem = [[NSMenuItem alloc] init];
	[mainMenu addItem:appItem];
	NSMenu *appMenu = [[NSMenu alloc] init];
	NSString *appName = [[NSProcessInfo processInfo] processName];
	[appMenu addItemWithTitle:[@"About " stringByAppendingString:appName]
	                   action:@selector(orderFrontStandardAboutPanel:)
	            keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *hide = [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:appName]
	                                      action:@selector(hide:)
	                               keyEquivalent:@"h"];
	hide.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
	                                            action:@selector(hideOtherApplications:)
	                                     keyEquivalent:@"h"];
	hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
	[appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *quit = [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
	                                      action:@selector(terminate:)
	                               keyEquivalent:@"q"];
	quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	appItem.submenu = appMenu;

	NSMenuItem *editItem = [[NSMenuItem alloc] init];
	[mainMenu addItem:editItem];
	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	[editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
	NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
	redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
	editItem.submenu = editMenu;

	NSMenuItem *windowItem = [[NSMenuItem alloc] init];
	[mainMenu addItem:windowItem];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
	[windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	[windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
	windowItem.submenu = windowMenu;
	[NSApp setWindowsMenu:windowMenu];

	[NSApp setMainMenu:mainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
	(void)note;
	if (self.geaDidFinishBoot) return;
	self.geaDidFinishBoot = YES;
	gea_macos_smoke_log("[gea-macos] applicationDidFinishLaunching");
	gGeaAppDelegate = self;

	// Report the Mac's real link state through the WiFi facade before
	// Application::init — apps gate remote fetches on wifi().connected()
	// (e.g. maps skips tile downloads while it reads false).
	gea::macos::installWifiDriver();
	// macOS has an available host filesystem before app initialization.
	// ImageService gates external reads on this provider just as device targets
	// gate theirs on mounted storage.
	gea::platform::storage::setMountProvider(+[]() { return true; });
	const bool thermalrightTarget = gea::macos::thermalright::enabled();
	if (!thermalrightTarget) [self installMainMenu];

	// Register any .ttf / .otf the build script copied next to the binary.
	// Done before Application::init so @font-face declarations in the app's
	// CSS resolve to the registered family on first lookup.
	NSString *fontsDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Fonts"];
	gea::macos::registerCustomTtfDirectory(fontsDir);

	// Wire the AppManager platform so JSX-level Apps.launch('foo') opens
	// dist/foo/Foo.app and terminates this process. Derive the current app
	// id from CFBundleIdentifier (set by Info.plist.in to com.gea.<id>).
	NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
	NSString *currentId = [bundleId hasPrefix:@"com.gea."] ? [bundleId substringFromIndex:8] : @"";
	gea::macos::installAppLauncherPlatform(currentId.UTF8String);

	if (thermalrightTarget) {
		NSLog(@"[gea-thermalright] headless display target %dx%d",
		      gea::platform::display::kWidth,
		      gea::platform::display::kHeight);
		gea::framework::app::Application::init(gea::platform::display::kWidth,
		                                       gea::platform::display::kHeight);
		[self tick];
		[self startFrameTimer];
		return;
	}

	// Default window size — apps designed for the 410×502 hardware display
	// fit exactly. A per-app `macos.json` (copied into Resources/window.json
	// by the build script) opts into a larger desktop-class layout (e.g.
	// the notes-jsx example uses 1000×640 + transparent title bar so its
	// sidebar vibrancy reaches the top of the window). Env vars still
	// override for layout-debugging without touching the bundle.
	int winW = 410, winH = 502;
	int minW = 200, minH = 200;
	NSString *windowTitle = @"gea";
	BOOL fullSizeContentView = NO;
	BOOL transparentTitleBar = NO;
	BOOL titleHidden = NO;
	NSString *appearanceName = nil;

	NSString *cfgPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"window.json"];
	NSData *cfgData = [NSData dataWithContentsOfFile:cfgPath];
	if (cfgData) {
		NSError *err = nil;
		id parsed = [NSJSONSerialization JSONObjectWithData:cfgData options:0 error:&err];
		if ([parsed isKindOfClass:[NSDictionary class]]) {
			NSDictionary *cfg = parsed;
			NSDictionary *win = cfg[@"window"] ?: cfg;
			id w = win[@"width"];   if ([w respondsToSelector:@selector(intValue)]) winW = [w intValue];
			id h = win[@"height"];  if ([h respondsToSelector:@selector(intValue)]) winH = [h intValue];
			id mw = win[@"minWidth"];  if ([mw respondsToSelector:@selector(intValue)]) minW = [mw intValue];
			id mh = win[@"minHeight"]; if ([mh respondsToSelector:@selector(intValue)]) minH = [mh intValue];
			id t  = win[@"title"];  if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) windowTitle = t;
			id fsc = win[@"fullSizeContentView"]; if ([fsc respondsToSelector:@selector(boolValue)]) fullSizeContentView = [fsc boolValue];
			id ttb = win[@"titleBarTransparent"]; if ([ttb respondsToSelector:@selector(boolValue)]) transparentTitleBar = [ttb boolValue];
			id tv  = win[@"titleVisibility"];
			if ([tv isKindOfClass:[NSString class]] && [(NSString *)tv isEqualToString:@"hidden"]) titleHidden = YES;
			id ap = win[@"appearance"];
			if ([ap isKindOfClass:[NSString class]]) appearanceName = ap;
		}
	}

	if (const char *e = getenv("GEA_MACOS_WIN_W")) winW = atoi(e);
	if (const char *e = getenv("GEA_MACOS_WIN_H")) winH = atoi(e);
	NSRect frame = NSMakeRect(0, 0, winW, winH);
	NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	if (fullSizeContentView) styleMask |= NSWindowStyleMaskFullSizeContentView;
	self.window = [[NSWindow alloc] initWithContentRect:frame
	                                          styleMask:styleMask
	                                            backing:NSBackingStoreBuffered
	                                              defer:NO];
	[self.window setTitle:windowTitle];
	self.window.contentMinSize = NSMakeSize(minW, minH);
	self.window.delegate = self;
	if (transparentTitleBar) self.window.titlebarAppearsTransparent = YES;
	if (titleHidden) self.window.titleVisibility = NSWindowTitleHidden;
	if ([appearanceName isEqualToString:@"dark"]) {
		self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
	} else if ([appearanceName isEqualToString:@"light"]) {
		self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
	}
	[self.window center];

	self.rootView = [[GeaContentView alloc] initWithFrame:[self.window.contentView bounds]];
	self.rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[self.rootView setWantsLayer:YES];
	[self.window setContentView:self.rootView];
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];

	NSSize size = self.rootView.bounds.size;
	if (gea::macos::thermalright::enabled()) {
		size = NSMakeSize(gea::platform::display::kWidth, gea::platform::display::kHeight);
	}
	gea_macos_smoke_log("[gea-macos] before Application::init");
	gea::framework::app::Application::init(static_cast<int>(size.width), static_cast<int>(size.height));
	gea_macos_smoke_log("[gea-macos] after Application::init");

	// If the app's mounted root is a <glass-split>, swap the flat content view
	// for a native NSSplitViewController + NSToolbar shell. The shell installs
	// itself as window.contentViewController (replacing rootView) and renders
	// each pane's gea subtree into a real, resizable AppKit pane.
	if (!gea::macos::thermalright::enabled()) {
		int mountedRoot = gea::embedded::ui::Tree::instance().mountedRoot();
		if (mountedRoot >= 0) {
			self.splitShell = [GeaSplitShell shellForRootNode:mountedRoot window:self.window];
		}
	}

	[self tick];
	[self startFrameTimer];
}

- (void)startFrameTimer
{
#if defined(GEA_NATIVE_DEBUGGER) && GEA_NATIVE_DEBUGGER
	gea_macos_debugger_start();
#endif
	if (self.frameTimer) return;
	const BOOL thermalrightTarget = gea::macos::thermalright::enabled();
	if (!thermalrightTarget) {
		if (@available(macOS 14.0, *)) {
			if (self.frameDisplayLink) return;
			// A timer cannot express the desired display refresh rate. The
			// window's display link requests the screen's native cadence and
			// follows it when the window moves between displays.
			self.frameDisplayLink = [self.window displayLinkWithTarget:self
			                                                   selector:@selector(displayLinkDidFire:)];
			[self updateDisplayLinkRate];
			[self.frameDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
			return;
		}
	}
	// Older macOS versions rely on the blocking presentation swap for pacing.
	// A fast timer avoids losing a whole refresh when a swap spans a timer fire.
	const NSTimeInterval frameInterval = thermalrightTarget
		? (1.0 / static_cast<double>(gea::macos::thermalright::fps()))
		: (1.0 / 960.0);
	AppDelegate * __weak weakSelf = self;
	// Schedule on NSRunLoopCommonModes so the timer keeps firing during
	// NSEventTrackingRunLoopMode (live window-resize drag, menu tracking,
	// etc.) instead of pausing until the user releases the mouse.
	self.frameTimer = [NSTimer timerWithTimeInterval:frameInterval
	                                          repeats:YES
	                                            block:^(NSTimer *t) {
		(void)t;
		[weakSelf tick];
	}];
	self.frameTimer.tolerance = thermalrightTarget ? 0.001 : 0.0;
	[[NSRunLoop currentRunLoop] addTimer:self.frameTimer forMode:NSRunLoopCommonModes];
}

- (void)updateDisplayLinkRate
{
	NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
	const NSInteger maximumFPS = screen.maximumFramesPerSecond;
	const float fps = maximumFPS > 0 ? static_cast<float>(maximumFPS) : 60.0f;
	self.frameDisplayLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
}

- (void)displayLinkDidFire:(CADisplayLink *)displayLink
{
	static const bool profile = std::getenv("GEA_NATIVE_FRAME_PROFILE") != nullptr;
	if (!profile) {
		[self tick];
		return;
	}
	using Clock = std::chrono::steady_clock;
	const auto begin = Clock::now();
	[self tick];
	const auto end = Clock::now();
	static auto windowStart = begin;
	static double totalMs = 0.0;
	static double applicationMs = 0.0;
	static double maximumMs = 0.0;
	static unsigned frames = 0;
	const double elapsedMs = std::chrono::duration<double, std::milli>(end - begin).count();
	totalMs += elapsedMs;
	applicationMs += self.geaProfileApplicationMs;
	maximumMs = std::max(maximumMs, elapsedMs);
	++frames;
	const double windowMs = std::chrono::duration<double, std::milli>(end - windowStart).count();
	if (windowMs >= 1000.0) {
		NSScreen *screen = self.window.screen;
		std::fprintf(stderr,
		    "[gea.frame-profile] callbacks_hz=%.1f callback_mean_ms=%.3f application_mean_ms=%.3f callback_max_ms=%.3f "
		    "link_period_ms=%.3f screen_max_hz=%ld screen=%s\n",
		    frames * 1000.0 / windowMs, totalMs / frames, applicationMs / frames, maximumMs,
		    (displayLink.targetTimestamp - displayLink.timestamp) * 1000.0,
		    static_cast<long>(screen.maximumFramesPerSecond), screen.localizedName.UTF8String);
		frames = 0;
		totalMs = applicationMs = maximumMs = 0.0;
		windowStart = end;
	}
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
	(void)notification;
	if (@available(macOS 14.0, *)) {
		if (self.frameDisplayLink) [self updateDisplayLinkRate];
	}
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	(void)notification;
	[self.frameTimer invalidate];
	self.frameTimer = nil;
	if (@available(macOS 14.0, *)) {
		[self.frameDisplayLink invalidate];
		self.frameDisplayLink = nil;
	}
}

- (void)tick
{
	if (getenv("GEA_MACOS_TICK_DEBUG")) {
		static int tickCount = 0;
		tickCount++;
		if (tickCount <= 10 || tickCount % 60 == 0) {
			std::fprintf(stderr, "[gea-macos] tick %d now=%d\n", tickCount, gea_embedded_now_ms());
		}
	}
	// Drain any pending resident-app launch from the previous frame BEFORE
	// running app::frame for this tick. When the launcher's onPress called
	// Apps.launch('foo'), the registry pushed 'foo' onto its pending queue;
	// here we pop it, select it as the new active resident, and re-run
	// Application::init so its __gea_top_level mounts the new UI. After this
	// switch, Application::frame below targets the new resident.
#if GEA_MACOS_HAS_RESIDENT_APPS
	{
		char pendingId[64] = "";
		if (gea::framework::apps::ResidentApps::consumeLaunch(pendingId, sizeof(pendingId))) {
			if (gea::framework::apps::ResidentApps::select(pendingId)) {
				NSSize sz = gea::macos::thermalright::enabled()
					? NSMakeSize(gea::platform::display::kWidth, gea::platform::display::kHeight)
					: self.rootView.bounds.size;
				gea::macos::MacosRenderer::instance().teardown();
				// Node ids are recycled by the next mount, so animations still
				// running against the outgoing app's nodes must be dropped
				// before it is torn down (runtime.cpp does this via
				// LaunchSurface). The scan below restarts them for the new app.
				gea::css::AnimationEngine::instance().clear();
				gea::framework::app::Application::init(static_cast<int>(sz.width),
				                                       static_cast<int>(sz.height));
			}
		}
	}
#endif
	static const bool profile = std::getenv("GEA_NATIVE_FRAME_PROFILE") != nullptr;
	using Clock = std::chrono::steady_clock;
	const auto applicationBegin = profile ? Clock::now() : Clock::time_point{};
	[self.rootView geaPollGamepad];
	gea::framework::app::Application::frame(gea_embedded_now_ms());
	if (profile) self.geaProfileApplicationMs = std::chrono::duration<double, std::milli>(Clock::now() - applicationBegin).count();
	auto &tree = gea::embedded::ui::Tree::instance();
	int root = tree.mountedRoot();
	if (root < 0) return;

	// Drive the CSS animation clock. The embedded runtime loop does this in
	// core/packages/core/runtime.cpp (frame()); macOS has its own AppDelegate
	// loop and never compiled that file, so `data-anim` declarative animations
	// and @keyframes rules were registered and then never started or advanced —
	// every animated app rendered its first frame and froze. Mirrors
	// runtime.cpp: scan once per mounted app (activeId change, or exactly once
	// in a single-app build where activeId() is always null), then tick.
	{
		const char *active = nullptr;
#if GEA_MACOS_HAS_RESIDENT_APPS
		active = gea::framework::apps::ResidentApps::activeId();
#endif
		static char lastScannedAnim[64] = {0};
		static bool singleAppAnimScanned = false;
		const bool shouldScan = active ? std::strcmp(active, lastScannedAnim) != 0 : !singleAppAnimScanned;
		if (shouldScan) {
			if (active)
				std::strncpy(lastScannedAnim, active, sizeof(lastScannedAnim) - 1);
			else
				singleAppAnimScanned = true;
			gea::css::DeclarativeAnimations::scanAndStart(gea_embedded_now_ms());
		}
	}
	gea::embedded::ui::StyleSheet::instance().startCssAnimations(gea_embedded_now_ms());
	gea::css::AnimationEngine::instance().tick(
	    static_cast<std::uint32_t>(gea_embedded_now_ms()));

	if (gea::macos::thermalright::enabled()) return;

	// Type into the first <input>/<textarea> without a keyboard. Set
	// GEA_MACOS_SYNTH_INPUT=<text> to run the app's own onInput path (value
	// attribute write + PointerEventType::Input dispatch) once, a few frames in.
	// Unlike GEA_MACOS_SYNTH_CLICK this does NOT exit, so the resulting frame can
	// be screenshotted. Posting real key events needs Accessibility permission,
	// which a scripted run does not have — this is how the text-input path stays
	// regression-testable from a shell. Placed ahead of the split-shell branch so
	// it runs for both shell and flat apps.
	if (const char *inputEnv = getenv("GEA_MACOS_SYNTH_INPUT")) {
		static int inputFrameCount = 0;
		++inputFrameCount;
		if (inputFrameCount == 4) {
			const int node = gea_macos_fire_input_for_node(-1, inputEnv);
			NSLog(@"[gea-synth-input] node=%d text=%s", node, inputEnv);
		}
	}

	// Native split-shell apps: each pane lays out + syncs against its own
	// resizable AppKit container. Skip the flat single-view path entirely.
	if (self.splitShell) {
		[self.splitShell layoutAndSync];
		return;
	}

	NSSize size = self.rootView.bounds.size;
	const int w = static_cast<int>(size.width);
	const int h = static_cast<int>(size.height);
	// macOS target convention: the mounted root view fills the window. This
	// gives apps a viewport that tracks resize without per-app code; if an
	// app wants different sizing it puts a sized child inside the root.
	gea::embedded::ui::NodeHandle(root).style().width(w);
	gea::embedded::ui::NodeHandle(root).style().height(h);
	tree.computeLayout(root, w, h);
	gea::macos::MacosRenderer::instance().sync(self.rootView, root);


 // Opt-in deterministic Gea event replay for recorded demos. No OS events or
 // application state shortcuts; the same tree handlers process every step.
 if (const char *planPath = getenv("GEA_MACOS_REPLAY_PLAN")) {
  static NSArray *steps = nil;
  static NSUInteger nextStep = 0;
  static NSDictionary *pending = nil;
  static int settleFrames = 0;
  static double startedAt = 0;
  auto replayLog = [&](NSDictionary *entry) {
   const char *logPath = getenv("GEA_MACOS_REPLAY_LOG");
   if (!logPath) return;
   NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
   FILE *file = std::fopen(logPath, "a");
   if (file) { std::fwrite(json.bytes, 1, json.length, file); std::fputc('\n', file); std::fclose(file); }
  };
  auto replayFail = [&](NSString *reason) {
   replayLog(@{@"error":reason}); NSLog(@"[gea-replay] %@", reason); std::exit(2);
  };
  if (!steps) {
   NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:planPath]];
   NSDictionary *plan = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
   if (![plan isKindOfClass:[NSDictionary class]] || ![plan[@"steps"] isKindOfClass:[NSArray class]]) replayFail(@"Invalid replay plan");
   steps = plan[@"steps"];
  }
  if (!startedAt) {
   const char *marker = getenv("GEA_MACOS_REPLAY_START");
   NSString *value = marker ? [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:marker] encoding:NSUTF8StringEncoding error:nil] : nil;
   startedAt = value.doubleValue;
  }
  if (startedAt) {
   const double elapsed = NSDate.date.timeIntervalSince1970 - startedAt;
   if (pending && ++settleFrames >= 3) {
    NSString *expected = pending[@"expect"];
    std::string text;
    for (int i=0;i<tree.nodeCount();++i) { text += tree.node(i).text; text += " "; }
    if (expected.length && text.find(expected.UTF8String) == std::string::npos) replayFail([NSString stringWithFormat:@"Step %@ did not show %@", pending[@"label"], expected]);
    if (NSDictionary *check=pending[@"expectTextIn"]) {
     auto subtreeText = [&](auto &&visit, int node) -> std::string {
      std::string result=tree.node(node).text; result += " ";
      for(int child=tree.node(node).first_child;child>=0;child=tree.node(child).next_sibling) result += visit(visit,child);
      return result;
     };
     bool matched=false;
     for(int i=0;i<tree.nodeCount();++i) if(tree.className(i).find([check[@"class"] UTF8String])!=std::string::npos) {
      std::string raw=subtreeText(subtreeText,i);
      NSString *value=[NSString stringWithUTF8String:raw.c_str()];
      NSMutableArray *words=[NSMutableArray array];
      for(NSString *word in [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if(word.length) [words addObject:word];
      if([[words componentsJoinedByString:@" "] containsString:check[@"contains"]]) matched=true;
     }
     if(!matched) replayFail([NSString stringWithFormat:@"Step %@ did not show %@ in %@",pending[@"label"],check[@"contains"],check[@"class"]]);
    }
    replayLog(@{@"verified":pending[@"label"], @"elapsed":@(elapsed)});
    pending = nil;
   }
   if (!pending && nextStep < steps.count && elapsed >= [steps[nextStep][@"at"] doubleValue]) {
    NSDictionary *step = steps[nextStep++];
    using gea::framework::events::PointerEvent;
    using gea::framework::events::PointerEventType;
    if (NSString *text = step[@"text"]) {
     const int inputRoot = geaCustomInputRoot();
     if (inputRoot < 0) replayFail(@"No Gea input root");
     tree.setAttribute(inputRoot,"value",text.UTF8String);
     PointerEvent event; event.type=PointerEventType::Input; event.targetId=inputRoot; tree.dispatchEvent(event);
    } else {
     const int x=[step[@"x"] intValue], y=[step[@"y"] intValue];
     NSPoint point=NSMakePoint(x,self.rootView.bounds.size.height-y);
     NSView *hit=[self.rootView hitTest:[self.rootView convertPoint:point toView:self.rootView.superview]];
     int target=gea::macos::nodeIdForView(hit), ancestor=target;
     const std::string expected=[step[@"target"] UTF8String];
     while (ancestor>=0 && tree.className(ancestor).find(expected)==std::string::npos) ancestor=tree.node(ancestor).parent;
     if (target<0 || ancestor<0) replayFail([NSString stringWithFormat:@"Wrong hit target for %@",step[@"label"]]);
     tree.pointerHover(x,y);
     if (!geaOwnsContourPress(x,y)) tree.pointerDown(x,y);
     dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
      gea::embedded::ui::Tree::instance().pointerUp();
     });
     for (auto phase : {PointerEventType::TouchStart,PointerEventType::TouchEnd,PointerEventType::Click}) {
      PointerEvent event; event.type=phase; event.targetId=target; event.pointerId=1;
      event.x=x; event.y=y; event.clientX=x; event.clientY=y; event.pageX=x; event.pageY=y;
      tree.dispatchEvent(event);
     }
    }
    replayLog(@{@"action":step[@"label"], @"elapsed":@(elapsed), @"index":@(nextStep-1)});
    pending=step; settleFrames=0;
   }
  }
 }

	if (const char *clickEnv = getenv("GEA_MACOS_SYNTH_CLICK")) {
		static int frameCount = 0;
		++frameCount;
		if (frameCount == 3) {
			extern void gea_macos_fire_press_for_node(int);
			gea_macos_fire_press_for_node(atoi(clickEnv));
		} else if (frameCount == 8) {
			NSLog(@"[gea-synth] rootView frame=%@ bounds=%@",
			      NSStringFromRect(self.rootView.frame),
			      NSStringFromRect(self.rootView.bounds));
			[self walkAndLogSubviews:self.rootView indent:@"  "];
			exit(0);
		}
	}
	// Dump tree layout + NSView hierarchy on the first frame to stderr. Set
	// GEA_MACOS_LAYOUT_DUMP=1 to enable; lets you see root size, child positions
	// and how they map to NSView frames so layout vs. y-flip bugs are diagnosable.
	if (getenv("GEA_MACOS_LAYOUT_DUMP")) {
		static int dumpFrame = 0;
		++dumpFrame;
		// First few frames after launch, then every 60th frame so we can catch
		// "renders correctly on frame 1, breaks on frame 2" patterns.
		if (dumpFrame <= 5 || dumpFrame % 60 == 0) {
			NSLog(@"[gea-layout] frame=%d rootView=%@ window=%dx%d",
			      dumpFrame, NSStringFromRect(self.rootView.frame), w, h);
			using gea::embedded::ui::NodeType;
			for (int i = 0; i < tree.nodeCount(); i++) {
				const auto &n = tree.node(i);
				NSLog(@"  node[%d] t=%d xy=(%d,%d) wh=(%dx%d)%s",
				      i, (int)n.type,
				      (int)n.layout.x, (int)n.layout.y,
				      (int)n.layout.width, (int)n.layout.height,
				      n.type == NodeType::Text && !n.text.empty() ? n.text.c_str() : "");
			}
			[self walkAndLogSubviews:self.rootView indent:@"  "];
		}
	}
	if (getenv("GEA_MACOS_VERIFY_ONCE")) {
		static BOOL logged = NO;
		if (!logged) {
			logged = YES;
			using gea::embedded::ui::NodeType;
			NSLog(@"[gea-verify] mountedRoot=%d nodeCount=%d subviews=%lu",
			      root, tree.nodeCount(), (unsigned long)self.rootView.subviews.count);
			int buttonNode = -1;
			for (int i = 0; i < tree.nodeCount(); i++) {
				const auto &n = tree.node(i);
				NSLog(@"[gea-verify]   node[%d] type=%d frame=(%d,%d,%dx%d)",
				      i, (int)n.type, (int)n.layout.x, (int)n.layout.y,
				      (int)n.layout.width, (int)n.layout.height);
				if (n.type == NodeType::Button) buttonNode = i;
			}
			[self walkAndLogSubviews:self.rootView indent:@"  "];
			if (buttonNode >= 0) {
				NSLog(@"[gea-verify] firing press for buttonNode=%d twice", buttonNode);
				gea_macos_fire_press_for_node(buttonNode);
				gea_macos_fire_press_for_node(buttonNode);
				for (int i = 0; i < tree.nodeCount(); i++) {
					const auto &n = tree.node(i);
					if (n.type == NodeType::Text && !n.text.empty()) {
						NSLog(@"[gea-verify]   text node[%d] = \"%s\"", i, n.text.c_str());
					}
				}
			}
			exit(0);
		}
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;
	if (gea::macos::thermalright::enabled()) return NO;
	return YES;
}

// Apple-native entry point: replace the window's flat content view with the
// AppKit object graph the TS program built. The view fills the content area and
// tracks window resizes; the app's own view controllers manage internal layout.
- (void)installNativeRootView:(NSView *)view
{
	if (gea::macos::thermalright::enabled()) return;
	if (!view) return;
	self.rootView = nil;  // drop the gea flat content view; unused in this mode
	view.frame = [self.window.contentView bounds];
	view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	[self.window setContentView:view];
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)windowDidResize:(NSNotification *)notification
{
	(void)notification;
	if (gea::macos::thermalright::enabled()) return;
	if (!self.splitShell) {
		const NSSize size = self.rootView.bounds.size;
		const int width = static_cast<int>(size.width), height = static_cast<int>(size.height);
		if (width > 0 && height > 0 &&
		    (width != gea::embedded::ui::Document::preferredMountWidth() ||
		     height != gea::embedded::ui::Document::preferredMountHeight())) {
			gea::embedded::ui::Document::setPreferredMountSize(width, height);
			// AppKit layout uses points; a CSS px is one point, including on Retina.
			gea::embedded::ui::setViewportMetrics(width, height, 1.0);
		}
	}
	// Sync immediately on resize end too; the live-mode timer covers the
	// drag, this handles the final snap.
	[self tick];
}

- (void)walkAndLogSubviews:(NSView *)view indent:(NSString *)indent
{
	for (NSView *sv in view.subviews) {
		NSString *extra = @"";
		if ([sv isKindOfClass:[NSTextField class]]) {
			NSTextField *tf = (NSTextField *)sv;
			extra = [NSString stringWithFormat:@" text=\"%@\" font=%@/%g",
			         tf.stringValue, tf.font.familyName, tf.font.pointSize];
		} else if ([sv isKindOfClass:[NSButton class]]) {
			extra = [NSString stringWithFormat:@" title=\"%@\"", ((NSButton *)sv).title];
		}
		CALayer *L = sv.layer;
		NSString *layerInfo = L ? [NSString stringWithFormat:
		         @" L.frame=%@ L.pos=(%g,%g) L.anchor=(%g,%g) L.bg=%@",
		         NSStringFromRect(NSRectFromCGRect(L.frame)),
		         L.position.x, L.position.y,
		         L.anchorPoint.x, L.anchorPoint.y,
		         L.backgroundColor ? @"set" : @"nil"] : @"";
		NSLog(@"[gea-verify]%@ %@ frame=%@%@%@", indent,
		      NSStringFromClass([sv class]),
		      NSStringFromRect(sv.frame),
		      layerInfo,
		      extra);
		[self walkAndLogSubviews:sv indent:[indent stringByAppendingString:@"  "]];
	}
}

@end

#if GEA_MACOS_HAS_APPLE_NATIVE_BRIDGE
// Implements the @geajs/apple/AppKit `installRootView(view)` entry. geatsc lowers
// the TS call to `gea::apple::AppKit::installRootView(NSView)`; we unwrap the
// handle-table object back to a real ::NSView and hand it to the delegate.
void gea::apple::AppKit::installRootView(gea::apple::AppKit::NSView view)
{
	::NSView *nativeView = (__bridge ::NSView *)gea::apple::objc::object(view.handle);
	if (!nativeView) return;
	AppDelegate *delegate = gGeaAppDelegate;
	if (!delegate) return;
	if ([NSThread isMainThread]) {
		[delegate installNativeRootView:nativeView];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate installNativeRootView:nativeView];
		});
	}
}

// Implements @geajs/apple/AppKit installRootViewController(vc). Sets the window's
// contentViewController, so an NSSplitViewController (with sidebar/content/detail
// items) drives the whole window — Liquid Glass sidebar, resizable dividers, and
// the unified-toolbar safe area all come for free, exactly like real Notes.
void gea::apple::AppKit::installRootViewController(gea::apple::AppKit::NSViewController viewController)
{
	::NSViewController *vc = (__bridge ::NSViewController *)gea::apple::objc::object(viewController.handle);
	if (!vc) return;
	AppDelegate *delegate = gGeaAppDelegate;
	if (!delegate) return;
	auto install = ^{
		// Setting contentViewController makes AppKit resize the window to the split
		// view's fitting (minimum-thickness) size, discarding the configured
		// macos.json size. Capture the configured content size first and restore it
		// after the swap so the window opens at the size the app asked for.
		NSSize wantedContent = delegate.window.contentView.bounds.size;
		delegate.window.contentViewController = vc;
		if (wantedContent.width > 1.0 && wantedContent.height > 1.0) {
			[delegate.window setContentSize:wantedContent];
			[delegate.window center];
		}
		[delegate.window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
		// Clear the initial first responder so an editable NSTextField/NSTextView
		// in the content doesn't grab focus (drawing a blue focus ring + selecting
		// its text) the instant the window opens — matching a freshly launched
		// document app, which shows no focused field until the user clicks one.
		[delegate.window makeFirstResponder:nil];
	};
	if ([NSThread isMainThread]) install();
	else dispatch_async(dispatch_get_main_queue(), install);
}

// Vends the toolbar items declared by AppKit::installToolbar's spec string,
// matching the reference's GeaSplitShell toolbar: bordered image buttons with a
// label/tooltip and a target/action (so they render enabled, not dimmed). The
// sidebar toggle rides the responder chain to NSSplitViewController.toggleSidebar:,
// the compose item invokes the New Note ObjCTarget, and the rest are inert (a
// no-op action keeps them enabled and bordered, exactly like the reference's
// data-action-less items). Held strongly by AppDelegate.geaToolbarDelegate
// because NSToolbar.delegate is weak.
@interface GeaAppleToolbarDelegate : NSObject <NSToolbarDelegate>
@property(nonatomic, strong) NSArray<NSToolbarItemIdentifier> *ids;
@property(nonatomic, strong) NSDictionary<NSToolbarItemIdentifier, NSString *> *symbols;
@property(nonatomic, copy) NSString *searchId;
@property(nonatomic, strong) id composeTarget;
@end

@implementation GeaAppleToolbarDelegate
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.ids; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.ids; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	(void)toolbar;
	(void)flag;
	if (self.searchId && [identifier isEqualToString:self.searchId]) {
		if (@available(macOS 11.0, *)) {
			NSSearchToolbarItem *search = [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];
			search.resignsFirstResponderWithCancel = YES;
			return search;
		}
		NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
		item.view = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 180, 22)];
		return item;
	}
	NSString *symbol = self.symbols[identifier];
	if (!symbol) return nil;
	NSDictionary<NSString *, NSString *> *labels = @{
		@"sidebar.left" : @"Toggle Sidebar",
		@"square.and.pencil" : @"New Note",
		@"textformat" : @"Format",
		@"checklist" : @"Checklist",
		@"tablecells" : @"Table",
		@"square.and.arrow.up" : @"Share",
	};
	NSString *label = labels[symbol] ?: symbol;
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
	item.label = label;
	item.toolTip = label;
	if (@available(macOS 11.0, *)) {
		item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
	}
	item.bordered = YES;
	if ([symbol isEqualToString:@"sidebar.left"]) {
		item.action = @selector(toggleSidebar:);
		item.target = nil; // responder chain → NSSplitViewController
	} else if ([symbol isEqualToString:@"square.and.pencil"] && self.composeTarget) {
		item.target = self.composeTarget;
		item.action = @selector(invoke:);
	} else {
		item.target = self;
		item.action = @selector(toolbarNoop:);
	}
	return item;
}
- (void)toolbarNoop:(id)sender { (void)sender; }
@end

// Implements @geajs/apple/AppKit installToolbar(spec, composeTarget). `spec` is a
// comma-separated list: an SF Symbol name => bordered image button, `space` =>
// flexible space, `search` => search field. Builds a real unified-title-bar
// NSToolbar and attaches it. `composeTarget` is invoked by the compose item.
void gea::apple::AppKit::installToolbar(std::string spec, gea::apple::Foundation::NSObject composeTargetWrapper)
{
	AppDelegate *delegate = gGeaAppDelegate;
	if (!delegate) return;
	NSString *specStr = [NSString stringWithUTF8String:spec.c_str()];
	id composeTarget = (__bridge id)gea::apple::objc::object(composeTargetWrapper.handle);
	auto install = ^{
		NSMutableArray<NSToolbarItemIdentifier> *ids = [NSMutableArray array];
		NSMutableDictionary<NSToolbarItemIdentifier, NSString *> *symbols = [NSMutableDictionary dictionary];
		NSString *searchId = nil;
		int index = 0;
		for (NSString *raw in [specStr componentsSeparatedByString:@","]) {
			NSString *tok = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if (tok.length == 0) continue;
			if ([tok isEqualToString:@"space"]) {
				[ids addObject:NSToolbarFlexibleSpaceItemIdentifier];
			} else if ([tok isEqualToString:@"search"]) {
				searchId = @"gea.toolbar.search";
				[ids addObject:searchId];
			} else {
				NSString *iid = [NSString stringWithFormat:@"gea.toolbar.item.%d", index++];
				symbols[iid] = tok;
				[ids addObject:iid];
			}
		}
		GeaAppleToolbarDelegate *d = [[GeaAppleToolbarDelegate alloc] init];
		d.ids = ids;
		d.symbols = symbols;
		d.searchId = searchId;
		d.composeTarget = composeTarget;
		delegate.geaToolbarDelegate = d;
		NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"gea.apple.toolbar"];
		tb.delegate = d;
		tb.displayMode = NSToolbarDisplayModeIconOnly;
		tb.allowsUserCustomization = NO;
		delegate.window.toolbar = tb;
		if (@available(macOS 11.0, *)) delegate.window.toolbarStyle = NSWindowToolbarStyleUnified;
	};
	if ([NSThread isMainThread]) install();
	else dispatch_async(dispatch_get_main_queue(), install);
}

// A top-left-origin container. NSScrollView document views default to NSView's
// bottom-left origin, so a tall vertical list opens scrolled to the bottom. A
// flipped document view lays content out top-down and opens at the top.
@interface GeaFlippedView : NSView
@end
@implementation GeaFlippedView
- (BOOL)isFlipped { return YES; }
@end

// Implements @geajs/apple/AppKit setScrollDocumentTopAligned(scrollView, content).
void gea::apple::AppKit::setScrollDocumentTopAligned(gea::apple::AppKit::NSScrollView scrollWrapper,
                                                     gea::apple::AppKit::NSView contentWrapper)
{
	::NSScrollView *sv = (__bridge ::NSScrollView *)gea::apple::objc::object(scrollWrapper.handle);
	::NSView *content = (__bridge ::NSView *)gea::apple::objc::object(contentWrapper.handle);
	if (!sv || !content) return;
	auto install = ^{
		GeaFlippedView *flip = [[GeaFlippedView alloc] initWithFrame:NSZeroRect];
		flip.translatesAutoresizingMaskIntoConstraints = NO;
		content.translatesAutoresizingMaskIntoConstraints = NO;
		[flip addSubview:content];
		[::NSLayoutConstraint activateConstraints:@[
			[content.topAnchor constraintEqualToAnchor:flip.topAnchor],
			[content.leadingAnchor constraintEqualToAnchor:flip.leadingAnchor],
			[content.trailingAnchor constraintEqualToAnchor:flip.trailingAnchor],
			[content.bottomAnchor constraintEqualToAnchor:flip.bottomAnchor],
		]];
		sv.documentView = flip;
		// Pin the flipped document to the scroll's clip view: it tracks the clip
		// width (no horizontal scroll) while its height grows with the content
		// (vertical scroll), and its top aligns with the clip's top.
		[::NSLayoutConstraint activateConstraints:@[
			[flip.topAnchor constraintEqualToAnchor:sv.contentView.topAnchor],
			[flip.leadingAnchor constraintEqualToAnchor:sv.contentView.leadingAnchor],
			[flip.trailingAnchor constraintEqualToAnchor:sv.contentView.trailingAnchor],
			[flip.widthAnchor constraintEqualToAnchor:sv.contentView.widthAnchor],
		]];
	};
	if ([NSThread isMainThread]) install();
	else dispatch_async(dispatch_get_main_queue(), install);
}
#endif

int main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;
	@autoreleasepool {
		gea_macos_smoke_log("[gea-macos] main entered");
		NSApplication *app = [NSApplication sharedApplication];
		AppDelegate *delegate = [[AppDelegate alloc] init];
		[app setDelegate:delegate];
		[app setActivationPolicy:gea::macos::thermalright::enabled()
			? NSApplicationActivationPolicyProhibited
			: NSApplicationActivationPolicyRegular];
		gea_macos_smoke_log("[gea-macos] before finishLaunching");
		[app finishLaunching];
		gea_macos_smoke_log("[gea-macos] after finishLaunching");
		gea_macos_smoke_log("[gea-macos] before explicit delegate launch");
		NSNotification *launchNotification =
			[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app];
		[delegate applicationDidFinishLaunching:launchNotification];
		gea_macos_smoke_log("[gea-macos] after explicit delegate launch");
		gea_macos_smoke_log("[gea-macos] before NSApplication run");
		[app run];
		gea_macos_smoke_log("[gea-macos] after NSApplication run");
	}
	return 0;
}

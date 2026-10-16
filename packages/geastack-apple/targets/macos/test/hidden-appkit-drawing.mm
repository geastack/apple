#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include "macos_background_test.h"
#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <unistd.h>
// This isolated process never permits a user-visible application lifecycle.
@interface ReferenceNeverActiveApplication:NSApplication
@end
@implementation ReferenceNeverActiveApplication
- (void)activateIgnoringOtherApps:(BOOL)flag{gea::macos::background_test::refuse("application activation forbidden");}
- (void)activate{gea::macos::background_test::refuse("application activation forbidden");}
- (void)unhide:(id)sender{gea::macos::background_test::refuse("application unhide forbidden");}
- (void)unhideWithoutActivation{gea::macos::background_test::refuse("application unhide forbidden");}
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy{if(policy!=NSApplicationActivationPolicyProhibited)gea::macos::background_test::refuse("only prohibited activation policy allowed");return[super setActivationPolicy:policy];}
@end
@interface ReferenceNeverFrontWindow:NSWindow
@end
@implementation ReferenceNeverFrontWindow
- (BOOL)canBecomeKeyWindow{return NO;}
- (BOOL)canBecomeMainWindow{return NO;}
- (void)makeKeyAndOrderFront:(id)sender{gea::macos::background_test::refuse("front forbidden");}
- (void)makeKeyWindow{gea::macos::background_test::refuse("key forbidden");}
- (void)makeMainWindow{gea::macos::background_test::refuse("main forbidden");}
- (void)orderFront:(id)sender{gea::macos::background_test::refuse("front forbidden");}
- (void)orderFrontRegardless{gea::macos::background_test::refuse("front forbidden");}
- (void)orderWindow:(NSWindowOrderingMode)p relativeTo:(NSInteger)n{gea::macos::background_test::refuse("order forbidden");}
@end
@interface ReferenceAction:NSObject
@property(nonatomic) int count;
- (void)fire:(id)sender;
@end
@implementation ReferenceAction
- (void)fire:(id)sender{++_count;}
@end
static void settle(NSView*v){[v layoutSubtreeIfNeeded];[v setNeedsDisplay:YES];for(NSView*c in v.subviews)settle(c);[v displayIfNeeded];}
static void save(NSData*data,NSString*path){assert(data.length);assert(![[NSFileManager defaultManager]fileExistsAtPath:path]);assert([data writeToFile:path options:NSDataWritingWithoutOverwriting error:nil]);}
int main(){@autoreleasepool{
 alarm(12);if(!gea::macos::background_test::enabled())gea::macos::background_test::refuse("explicit mode required");const char*audio=getenv("GEA_AUDIO_DISABLED");if(!audio||strcmp(audio,"1"))gea::macos::background_test::refuse("audio fence required");
 const char*out=getenv("GEA_NATIVE_SNAPSHOT");if(!out)gea::macos::background_test::refuse("fresh snapshot path required");NSString*path=[NSString stringWithUTF8String:out];const char*dir=getenv("GEA_NATIVE_SNAPSHOT_DIR");if(!dir||dir[0]!='/')gea::macos::background_test::refuse("snapshot directory required");if(![path hasPrefix:[[NSString stringWithUTF8String:dir]stringByAppendingString:@"/hidden-appkit-drawing-"]]||[path containsString:@"/../"])gea::macos::background_test::refuse("snapshot path refused");
 pid_t before=NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;NSPoint pointer=NSEvent.mouseLocation;
 NSApplication*app=[ReferenceNeverActiveApplication sharedApplication];assert([app isKindOfClass:ReferenceNeverActiveApplication.class]);gea::macos::background_test::configure(app);
 assert(app.delegate==nil);[app finishLaunching];assert(app.delegate==nil);gea::macos::background_test::checkApplication(app);
 ReferenceNeverFrontWindow*w=[[ReferenceNeverFrontWindow alloc]initWithContentRect:NSMakeRect(0,0,640,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
 NSView*root=[[NSView alloc]initWithFrame:NSMakeRect(0,0,640,400)];root.wantsLayer=YES;w.contentView=root;
 NSButton*b=[[NSButton alloc]initWithFrame:NSMakeRect(0,360,160,40)];b.buttonType=NSButtonTypeMomentaryLight;b.bezelStyle=NSBezelStyleRounded;b.wantsLayer=YES;b.title=@"Native method";ReferenceAction*target=[ReferenceAction new];b.target=target;b.action=@selector(fire:);[root addSubview:b];
 NSTextField*field=[[NSTextField alloc]initWithFrame:NSMakeRect(0,320,200,40)];field.bezeled=NO;field.bordered=NO;field.drawsBackground=NO;field.wantsLayer=YES;field.stringValue=@"Native typed";field.textColor=[NSColor colorWithSRGBRed:11./255 green:12./255 blue:14./255 alpha:1];field.layer.backgroundColor=[NSColor colorWithSRGBRed:243./255 green:240./255 blue:233./255 alpha:1].CGColor;[root addSubview:field];
 NSPopUpButton*popup=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,240,200,40) pullsDown:NO];[popup addItemsWithTitles:@[@"a",@"b"]];[popup selectItemAtIndex:1];[root addSubview:popup];
 gea::macos::background_test::present(w);gea::macos::background_test::checkApplication(app);
 // Capture-only: no mouse/key tracking, action, or focus methods are invoked.

 settle(root);[CATransaction flush];
 fprintf(stderr,"appearance comparison: current=%s effectiveRoot=%s effectiveButton=%s cellTitle=%s cellType=%s\n",NSAppearance.currentDrawingAppearance.name.UTF8String,root.effectiveAppearance.name.UTF8String,b.effectiveAppearance.name.UTF8String,((NSButtonCell*)b.cell).title.UTF8String,NSStringFromClass(b.cell.class).UTF8String);
 [root.effectiveAppearance performAsCurrentDrawingAppearance:^{
 NSBitmapImageRep*rep=[root bitmapImageRepForCachingDisplayInRect:root.bounds];assert(rep);[root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];save([rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}],path);
 NSBitmapImageRep*layer=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nullptr pixelsWide:1280 pixelsHigh:800 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];NSGraphicsContext*c=[NSGraphicsContext graphicsContextWithBitmapImageRep:layer];assert(c);CGContextScaleCTM(c.CGContext,2,2);[root.layer renderInContext:c.CGContext];save([layer representationUsingType:NSBitmapImageFileTypePNG properties:@{}],[path stringByAppendingString:@".layer.png"]);
 NSBitmapImageRep*label=[b bitmapImageRepForCachingDisplayInRect:b.bounds];[b cacheDisplayInRect:b.bounds toBitmapImageRep:label];save([label representationUsingType:NSBitmapImageFileTypePNG properties:@{}],[path stringByAppendingString:@".button.png"]);
 for(int interior=0;interior<2;++interior){NSBitmapImageRep*cellRep=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:nullptr pixelsWide:320 pixelsHigh:80 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];NSGraphicsContext*context=[NSGraphicsContext graphicsContextWithBitmapImageRep:cellRep];assert(context);[NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=context;CGContextScaleCTM(context.CGContext,2,2);[[NSColor whiteColor]setFill];NSRectFill(NSMakeRect(0,0,160,40));if(interior)[b.cell drawInteriorWithFrame:NSMakeRect(0,0,160,40) inView:b];else[b.cell drawWithFrame:NSMakeRect(0,0,160,40) inView:b];[NSGraphicsContext restoreGraphicsState];save([cellRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}],[path stringByAppendingString:interior?@".cell-interior.png":@".cell.png"]);}
 CGFloat low=1,high=0;for(NSInteger y=label.pixelsHigh/4;y<3*label.pixelsHigh/4;++y)for(NSInteger x=label.pixelsWide/5;x<4*label.pixelsWide/5;++x){NSColor*k=[[label colorAtX:x y:y]colorUsingColorSpace:NSColorSpace.sRGBColorSpace];CGFloat r,g,bl,a;[k getRed:&r green:&g blue:&bl alpha:&a];CGFloat v=.2126*r+.7152*g+.0722*bl;low=std::min(low,v);high=std::max(high,v);}
 fprintf(stderr,"plain AppKit appearance-bound drawing reference: title=%s font=%g appearance=%s titleAttributes=%s inputBG=%s sampleLow=%g sampleHigh=%g\n",b.title.UTF8String,b.font.pointSize,b.effectiveAppearance.name.UTF8String,[b.attributedTitle attributesAtIndex:0 effectiveRange:nullptr].description.UTF8String,field.layer.backgroundColor?[[NSColor colorWithCGColor:field.layer.backgroundColor]description].UTF8String:"nil",low,high);
 }];
 gea::macos::background_test::checkApplication(app);printf("{\"scope\":\"plain AppKit appearance and direct-cell drawing diagnostic only\",\"actions\":%d,\"foregroundBefore\":%d,\"foregroundAfter\":%d,\"pointerUnchanged\":%s,\"active\":false,\"visible\":false,\"key\":false,\"main\":false}\n",target.count,before,NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier,NSEqualPoints(pointer,NSEvent.mouseLocation)?"true":"false");return 0;
}}

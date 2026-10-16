#pragma once

#ifdef __OBJC__
#import <AppKit/AppKit.h>

@interface GeaRetiredPress : NSObject {
@private
 void *_geaRetiredState;
}
- (void)emitCancellation;
@end

@interface PressBridge : NSObject {
@private
 void *_geaPressState;
}
@property(nonatomic, assign) int nodeId;
// Non-pointer tracking is used only for genuine keyboard default activation.
- (NSUInteger)beginPress:(id)sender;
- (NSUInteger)beginKeyboardPress:(id)sender;
- (NSUInteger)beginPointerPress:(NSEvent *)event;
- (void)endPressTracking:(NSUInteger)ticket;
- (void)cancelPress:(id)sender;
// Close the old native binding before any cancellation callback can reenter.
- (GeaRetiredPress *)closeInputBinding;
- (void)fire:(id)sender;
@end
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Programmatic atomic activation. Physical controls use begin/release/cancel.
void gea_macos_fire_press_for_node(int nodeId);

#ifdef __cplusplus
}
#endif

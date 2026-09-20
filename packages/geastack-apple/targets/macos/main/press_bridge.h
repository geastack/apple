#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>

@interface PressBridge : NSObject
@property(nonatomic, assign) int nodeId;
- (void)fire:(id)sender;
@end
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Dispatches a Click + Press event to the given node id via Tree::dispatchEvent.
void gea_macos_fire_press_for_node(int nodeId);

#ifdef __cplusplus
}
#endif

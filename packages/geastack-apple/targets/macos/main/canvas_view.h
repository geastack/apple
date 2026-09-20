#pragma once

#ifdef __OBJC__
#import <AppKit/AppKit.h>

@interface GeaCanvasView : NSView
@property(nonatomic, assign) int nodeId;
@end
#endif

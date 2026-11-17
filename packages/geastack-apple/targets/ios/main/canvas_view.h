#pragma once

#import <UIKit/UIKit.h>

@interface GeaCanvasView : UIView
@property(nonatomic, assign) int nodeId;
// Shows the canvas node's current pixels.
- (void)present;
@end

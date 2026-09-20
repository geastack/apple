#pragma once

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>

// Native AppKit shell for apps whose mounted root is a `<glass-split>`.
//
// Instead of rendering the whole gea tree into one flat NSView, the shell
// maps the declared structure onto real AppKit containers:
//   <glass-split>          → NSSplitViewController (resizable dividers)
//     <toolbar>            → window NSToolbar (unified title bar, SF Symbols)
//     <glass-pane sidebar> → NSSplitViewItem sidebar behavior (Liquid Glass)
//     <glass-pane list>    → NSSplitViewItem content-list behavior
//     <glass-pane detail>  → NSSplitViewItem regular
// Each pane's gea subtree is laid out against the pane's live bounds and
// rendered into the pane's container view, so resizing a divider re-flows
// that pane's content natively.
@interface GeaSplitShell : NSObject

// Builds the shell if `rootNodeId` is a `<glass-split>`; installs the split
// controller as the window's contentViewController and the toolbar on the
// window. Returns nil when the root isn't a glass-split (caller falls back to
// the legacy single-content-view path).
+ (instancetype)shellForRootNode:(int)rootNodeId window:(NSWindow *)window;

// Per-frame: size each pane node to its container's current bounds, run the
// flex layout for that pane, and sync the gea subtrees into the pane views.
- (void)layoutAndSync;

@end
#endif

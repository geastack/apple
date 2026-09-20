#pragma once

#ifdef __OBJC__
@class NSView;
@class NSArray;
#else
struct NSView;
struct NSArray;
#endif

namespace gea::macos {

class MacosRenderer {
public:
	static MacosRenderer &instance();

	// Walks the laid-out node tree rooted at rootNodeId and updates a
	// parallel NSView tree under parentForRoot: creating views for new
	// nodes, removing views for nodes that disappeared, reparenting where
	// the tree shape changed, and applying frame/style.
	void sync(NSView *parentForRoot, int rootNodeId);

	// Multi-root variant for the native split shell: each pane is its own
	// layout root rendered into its own container view. paneViews[i] hosts
	// the subtree rooted at rootNodeIds[i]. A single combined unseen-sweep
	// runs across ALL panes so per-pane syncing never evicts another pane's
	// views (which a naive loop of sync() calls would, since each sync()
	// sweeps every map entry it didn't touch).
	void syncPanes(NSArray *paneViews, const int *rootNodeIds);

	// Drop all NSView associations and detach them from their parents.
	// Called on app teardown / tree clear.
	void teardown();

private:
	MacosRenderer() = default;
};

}  // namespace gea::macos

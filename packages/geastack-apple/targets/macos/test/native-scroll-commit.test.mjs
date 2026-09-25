// AppKit owns a scroll container's position, and the engine must be told it.
// Without the commit a trackpad scroll moved the NSScrollView document while
// Tree::scrollTop stayed 0: a VirtualList kept windowing rows for offset 0, so
// everything past its first window was blank, and `scroll` listeners (which
// Tree::setScrollTop dispatches) never fired.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const renderer = readFileSync(new URL('../main/macos_renderer.mm', import.meta.url), 'utf8')

const clipView = renderer.match(/@implementation GeaFlippedClipView[^]*?@end/)?.[0] ?? ''
assert.ok(clipView, 'GeaFlippedClipView must be implemented in macos_renderer.mm')
assert.match(clipView, /postsBoundsChangedNotifications = YES/, 'the clip view must post bounds changes')
assert.match(clipView, /NSViewBoundsDidChangeNotification/, 'the clip view must observe its own bounds changes')
assert.match(clipView, /tree\.setScrollTop\(self\.nodeId,/, 'a bounds change must be committed with Tree::setScrollTop')
assert.match(clipView, /if \(y < -0\.5 \|\| y > maxY \+ 0\.5\) return;/, 'an overscrolled (rubber-banding) offset must not be committed')
assert.match(clipView, /g_macosSyncDepth > 0[^]*dispatch_async/, 'a bounds change made during sync must be committed after the walk')

assert.match(
  renderer,
  /isKindOfClass:\[GeaFlippedClipView class\]\]\) \{\s*\(\(GeaFlippedClipView \*\)sv\.contentView\)\.nodeId = nodeId;/,
  'every plain scroll container must tell its clip view which node it scrolls',
)
assert.match(
  renderer,
  /parentForChildren = sv\.documentView[^]*?parentAbsYForChildren = node\.layout\.y - tree\.scrollTop\(nodeId\);/,
  'children of a scrolled container must be placed in document space, not offset twice',
)
for (const fn of ['void MacosRenderer::sync(', 'void MacosRenderer::syncPanes(']) {
  const body = renderer.slice(renderer.indexOf(fn), renderer.indexOf(fn) + 400)
  assert.match(body, /const GeaSyncDepthScope syncScope;/, `${fn} must mark the sync walk`)
}

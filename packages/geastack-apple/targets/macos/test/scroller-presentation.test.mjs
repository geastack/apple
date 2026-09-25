// A macOS scroll container must present its scroller without taking space the
// engine laid content out in. The engine reserves no scrollbar gutter on any
// target, so a legacy (always-shown) NSScroller narrowed the clip view under a
// full-width layout: the right strip of every row was hidden, and the document
// was wider than the clip, so it scrolled sideways.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const renderer = readFileSync(new URL('../main/macos_renderer.mm', import.meta.url), 'utf8')

const contentSize = renderer.match(/void applyScrollContentSize\([^]*?\n\}/)?.[0] ?? ''
assert.ok(contentSize, 'applyScrollContentSize must be defined in macos_renderer.mm')
assert.match(
  contentSize,
  /sv\.scrollerStyle = NSScrollerStyleOverlay;/,
  'a scroll container must keep an overlay scroller: a legacy one takes width the engine laid content out in',
)
assert.match(
  contentSize,
  /const CGFloat w = node\.layout\.width;/,
  'the document must keep the engine layout width, so no laid-out content falls outside it',
)

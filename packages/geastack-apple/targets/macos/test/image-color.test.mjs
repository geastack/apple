import { runNativeTest } from './native-harness.mjs'

if (process.platform !== 'darwin') {
  console.log('SKIP: the image bridge requires AppKit')
  process.exit(0)
}

// A decoded PNG reaches AppKit with every RGBA channel value intact, whole,
// cropped, cover-scaled and through an image node's source rectangle.
await runNativeTest('image-color-test', {
  sources: ['image_bridge.mm', 'color_convert.mm', 'macos_memory.cpp'],
  test: new URL('./image-color.mm', import.meta.url).pathname,
})

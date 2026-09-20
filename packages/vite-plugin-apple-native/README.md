# @geastack/vite-plugin-apple-native

Vite build plugin for Gea **Apple-native** targets (iOS / macOS). It lowers JSX
written against Apple framework view tags into imperative native-view
construction, so apps render through real UIKit/AppKit/MapKit/Metal views rather
than the gea web/embedded renderer.

It exports two plugins:

- **`appleNativeJsxPlugin()`** — transforms `.tsx` whose elements are Apple
  native views (`UIView`, `UILabel`, `UIButton`, `UIStackView`,
  `UIVisualEffectView`, `MKMapView`, `MTKView`, `NSView`, `NSStackView`, …) into
  `new <View>()` + property assignment + `addSubview`/`addArrangedSubview`
  trees. Stack-style containers use `addArrangedSubview`;
  `UIVisualEffectView` children go on `contentView`.
- **`geaEmptyIrPlugin()`** — writes an empty gea IR file to `$GEA_IR_OUT` at
  bundle close (native-rendered apps carry no gea component IR).

## Usage

```ts
// vite.config.ts
import { appleNativeJsxPlugin, geaEmptyIrPlugin } from '@geastack/vite-plugin-apple-native'

export default defineConfig({
  plugins: [appleNativeJsxPlugin(), geaEmptyIrPlugin()],
})
```

Consumed by the Apple example apps (`ios-*`, `notes-native`), which depend on
`@geastack/vite-plugin-apple-native` like any other package. Babel
(`@babel/parser`/`traverse`/`types`/`generator`) is a direct dependency of this
package and is resolved from here.

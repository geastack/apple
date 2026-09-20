# @geastack/apple-swiftui

Optional JSX-to-SwiftUI source helpers for Apple-native GeaStack targets. JSX
written against SwiftUI view names is turned into SwiftUI source text rather
than rendered by the Gea engine.

```sh
npm install @geastack/apple-swiftui
```

## Usage

Point the JSX runtime at the package and render:

```json
{ "compilerOptions": { "jsx": "react-jsx", "jsxImportSource": "@geastack/apple-swiftui" } }
```

```tsx
import { renderToSwiftUISource } from '@geastack/apple-swiftui'

const source = renderToSwiftUISource(
  <VStack spacing={8}>
    <Text>Hello</Text>
  </VStack>
)
```

`@geastack/apple-swiftui/jsx-runtime` provides `jsx`, `jsxs` and `Fragment`;
the root export provides `createSwiftUIElement` and `renderToSwiftUISource`
plus the `SwiftUIElement` and `SwiftUIProps` types.

This is an experimental helper for Apple-native prototypes and is not required
by the macOS or iOS targets.

## License

Apache-2.0. See `LICENSE`.

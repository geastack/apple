# @geastack/apple-swiftui

Optional JSX-to-SwiftUI source helpers for Apple-native GeaStack targets. JSX
written against SwiftUI view names is turned into SwiftUI source text rather
than rendered by the Gea engine.

```sh
npm install @geastack/apple-swiftui
```

## Usage

Build a tree with `createSwiftUIElement(type, props, ...children)` and render
it to source text:

```ts
import { createSwiftUIElement as h, renderToSwiftUISource } from '@geastack/apple-swiftui'

const source = renderToSwiftUISource(
  h('VStack', { spacing: 8 },
    h('Text', null, 'Hello'),
    h('Button', { action: 'count += 1' }, h('Text', null, 'Tap'))
  )
)
// VStack(spacing: 8) {
//   Text("Hello")
//   Button(action: { count += 1 }) {
//     Text("Tap")
//   }
// }
```

`Text` takes its string children, `VStack`/`HStack`/`ZStack` take a numeric
`spacing`, `Button` takes its body as a Swift source string in `action`, and
any other type name is emitted as a container with that name. `Fragment`
groups children without emitting a view: `h(Fragment, null, a, b)`.

## JSX

Set the JSX transform to this package in `tsconfig.json`:

```json
{ "compilerOptions": { "jsx": "react-jsx", "jsxImportSource": "@geastack/apple-swiftui" } }
```

and import the view names you use:

```tsx
import { Button, Text, VStack, renderToSwiftUISource } from '@geastack/apple-swiftui'

const source = renderToSwiftUISource(
  <VStack spacing={8}>
    <Text>Hello</Text>
    <Button action="count += 1">
      <Text>Tap</Text>
    </Button>
  </VStack>
)
```

`VStack`, `HStack`, `ZStack`, `Text` and `Button` are exported. For any other
view, call `createSwiftUIElement('Name', props, ...children)`.

## Exports

The root export provides the view names above, `Fragment`,
`createSwiftUIElement`, `renderToSwiftUISource` and the `SwiftUIElement`,
`SwiftUIProps`, `SwiftUIChild` and `SwiftUIElementType` types.
`@geastack/apple-swiftui/jsx-runtime` provides `jsx`, `jsxs`, `Fragment` and
the `JSX` namespace.

This is an experimental helper for Apple-native prototypes and is not required
by the macOS or iOS targets.

## License

Apache-2.0. See `LICENSE`.

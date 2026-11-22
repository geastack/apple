import assert from 'node:assert/strict'
import { test } from 'node:test'

import { Button, HStack, Text, VStack, renderToSwiftUISource } from '@geastack/apple-swiftui'
import { Fragment, jsx, jsxs } from '@geastack/apple-swiftui/jsx-runtime'

// The calls a `react-jsx` transform emits for the tree in jsx-types.tsx.
test('the JSX runtime renders SwiftUI source from the exported view names', () => {
  const tree = jsxs(VStack, {
    spacing: 8,
    children: [
      jsx(Text, { children: 'Hello' }),
      jsx(HStack, { children: jsx(Button, { action: 'count += 1', children: jsx(Text, { children: 'Tap' }) }) }),
      jsx(Fragment, { children: jsx(Text, { children: 'Done' }) })
    ]
  })
  assert.equal(
    renderToSwiftUISource(tree),
    ['VStack(spacing: 8) {', '  Text("Hello")', '  HStack {', '    Button(action: { count += 1 }) {', '      Text("Tap")', '    }', '  }', '  Text("Done")', '}'].join('\n')
  )
})

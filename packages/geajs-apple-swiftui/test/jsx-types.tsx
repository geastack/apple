// Type-checked only (tsconfig.test.json): JSX against the exported view names
// has to be accepted by a strict TypeScript project.
import { Button, HStack, Text, VStack, renderToSwiftUISource } from '@geastack/apple-swiftui'

export const source: string = renderToSwiftUISource(
  <VStack spacing={8}>
    <Text>Hello</Text>
    <HStack>
      <Button action="count += 1">
        <Text>Tap</Text>
      </Button>
    </HStack>
    <>
      <Text>Done</Text>
    </>
  </VStack>
)

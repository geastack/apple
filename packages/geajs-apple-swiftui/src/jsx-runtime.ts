import { Fragment, createSwiftUIElement, type SwiftUIElement, type SwiftUIElementType, type SwiftUIProps } from './index.js'

export { Fragment }

export function jsx(type: SwiftUIElementType, props: SwiftUIProps | null, key?: string | number): SwiftUIElement {
  return withKey(createSwiftUIElement(type, props), key)
}

export function jsxs(type: SwiftUIElementType, props: SwiftUIProps | null, key?: string | number): SwiftUIElement {
  return jsx(type, props, key)
}

function withKey(element: SwiftUIElement, key: string | number | undefined): SwiftUIElement {
  return key === undefined ? element : { ...element, key }
}

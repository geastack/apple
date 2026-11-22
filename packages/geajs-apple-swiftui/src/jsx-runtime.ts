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

// What the TypeScript JSX transform checks elements against when a project
// sets `jsxImportSource: "@geastack/apple-swiftui"`.
export namespace JSX {
  export type Element = SwiftUIElement
  export type ElementType = SwiftUIElementType
  export interface ElementChildrenAttribute {
    children: unknown
  }
  export interface IntrinsicAttributes {
    key?: string | number
  }
  export interface IntrinsicElements {
    [name: string]: SwiftUIProps
  }
}

export const Fragment = Symbol.for('@geajs/apple-swiftui.fragment')

export type SwiftUIElementType = string | typeof Fragment
export type SwiftUIPrimitiveChild = string | number | boolean | null | undefined
export type SwiftUIChild = SwiftUIPrimitiveChild | SwiftUIElement | SwiftUIChild[]

export interface SwiftUIProps {
  children?: SwiftUIChild
  [key: string]: unknown
}

export interface SwiftUIElement {
  type: SwiftUIElementType
  props: Record<string, unknown>
  key?: string | number | null
  children: SwiftUIChild[]
}

export function createSwiftUIElement(type: SwiftUIElementType, props: SwiftUIProps | null, ...children: SwiftUIChild[]): SwiftUIElement {
  const nextProps: Record<string, unknown> = { ...(props ?? {}) }
  const propChildren = nextProps.children as SwiftUIChild | undefined
  delete nextProps.children
  return {
    type,
    props: nextProps,
    children: [...childList(propChildren), ...children],
  }
}

export function renderToSwiftUISource(child: SwiftUIChild): string {
  return renderChild(child, 0).join('\n')
}

function renderChild(child: SwiftUIChild, depth: number): string[] {
  if (Array.isArray(child)) return child.flatMap((item) => renderChild(item, depth))
  if (isEmptyChild(child)) return []
  if (isSwiftUIElement(child)) return renderElement(child, depth)
  return [`${indent(depth)}Text(${swiftString(String(child))})`]
}

function renderElement(element: SwiftUIElement, depth: number): string[] {
  if (element.type === Fragment) return element.children.flatMap((child) => renderChild(child, depth))
  if (element.type === 'Text') return [`${indent(depth)}Text(${swiftString(textContent(element.children))})`]
  if (element.type === 'Button') return renderContainer(element, depth, `Button(action: { ${actionSource(element.props)} })`)
  return renderContainer(element, depth, viewHeader(element))
}

function renderContainer(element: SwiftUIElement, depth: number, header: string): string[] {
  const body = element.children.flatMap((child) => renderChild(child, depth + 1))
  if (body.length === 0) return [`${indent(depth)}${header}`]
  return [`${indent(depth)}${header} {`, ...body, `${indent(depth)}}`]
}

function viewHeader(element: SwiftUIElement): string {
  const type = String(element.type)
  if (type === 'VStack' || type === 'HStack' || type === 'ZStack') {
    const spacing = element.props.spacing
    return typeof spacing === 'number' ? `${type}(spacing: ${formatNumber(spacing)})` : type
  }
  return type
}

function textContent(children: SwiftUIChild[]): string {
  return children
    .flatMap((child) => primitiveText(child))
    .join('')
}

function primitiveText(child: SwiftUIChild): string[] {
  if (Array.isArray(child)) return child.flatMap(primitiveText)
  if (isEmptyChild(child) || isSwiftUIElement(child)) return []
  return [String(child)]
}

function actionSource(props: Record<string, unknown>): string {
  return typeof props.action === 'string' && props.action.trim() ? props.action.trim() : ''
}

function childList(child: SwiftUIChild | undefined): SwiftUIChild[] {
  if (child === undefined) return []
  return Array.isArray(child) ? child : [child]
}

function isSwiftUIElement(value: SwiftUIChild): value is SwiftUIElement {
  return typeof value === 'object' && value !== null && !Array.isArray(value) && 'type' in value && 'children' in value
}

function isEmptyChild(child: SwiftUIChild): child is null | undefined | false {
  return child === null || child === undefined || child === false
}

function swiftString(value: string): string {
  return JSON.stringify(value)
}

function formatNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : String(value)
}

function indent(depth: number): string {
  return '  '.repeat(depth)
}

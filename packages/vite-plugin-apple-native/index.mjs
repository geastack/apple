import { mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname } from 'node:path'

// Babel is a direct dependency of this package; resolve it from here so the
// plugin is self-contained regardless of which app consumes it.
const requireBabel = createRequire(import.meta.url)
const { parse } = requireBabel('@babel/parser')
const traverseModule = requireBabel('@babel/traverse')
const t = requireBabel('@babel/types')
const generateModule = requireBabel('@babel/generator')
const traverse = traverseModule.default || traverseModule
const generate = generateModule.default || generateModule

const nativeViewTags = new Set([
  // UIKit (iOS)
  'UIView',
  'UILabel',
  'UIButton',
  'UIImageView',
  'UIProgressView',
  'UISlider',
  'UISwitch',
  'UIStackView',
  'UIVisualEffectView',
  'MKMapView',
  'MTKView',
  // AppKit (macOS)
  'NSView',
  'NSStackView',
  'NSSplitView',
  'NSScrollView',
  'NSVisualEffectView',
  'NSBox',
  'NSTextField',
  'NSTextView',
  'NSImageView',
  'NSButton',
])

// Containers whose children are added via addArrangedSubview rather than
// addSubview — the view arranges them with Auto Layout (no manual frames).
const arrangedSubviewTags = new Set(['UIStackView', 'NSStackView', 'NSSplitView'])

export function appleNativeJsxPlugin() {
  let nextId = 0
  return {
    name: 'gea-apple-native-jsx',
    enforce: 'pre',
    transform(code, id) {
      if (!id.endsWith('.tsx')) return null
      nextId = 0
      let ast
      try {
        ast = parse(code, { sourceType: 'module', plugins: ['jsx', 'typescript'] })
      } catch (error) {
        error.message = `${error.message} while parsing ${id}: ${code.slice(0, 120).replace(/\s+/g, ' ')}`
        throw error
      }
      let changed = false
      traverse(ast, {
        JSXElement(path) {
          path.replaceWith(buildNativeViewExpression(path.node, () => `__geaNativeView${nextId++}`))
          path.skip()
          changed = true
        },
      })
      if (!changed) return null
      return { code: generate(ast, { comments: true }).code, map: null }
    },
  }
}

function buildNativeViewExpression(node, nextName) {
  const tag = jsxTagName(node.openingElement.name)
  if (!nativeViewTags.has(tag)) throw new Error(`Unsupported Apple native JSX tag <${tag}>`)
  const view = t.identifier(nextName())
  const statements = [
    t.variableDeclaration('const', [t.variableDeclarator(view, t.newExpression(t.identifier(tag), []))]),
  ]

  for (const attr of node.openingElement.attributes) {
    if (!t.isJSXAttribute(attr) || !t.isJSXIdentifier(attr.name)) {
      throw new Error(`Unsupported Apple native JSX attribute on <${tag}>`)
    }
    applyAttribute(statements, view, tag, attr.name.name, jsxAttributeValue(attr.value))
  }

  for (const child of node.children) {
    if (t.isJSXElement(child)) {
      statements.push(addSubviewStatement(view, tag, buildNativeViewExpression(child, nextName)))
    } else if (t.isJSXExpressionContainer(child) && !t.isJSXEmptyExpression(child.expression)) {
      statements.push(addSubviewStatement(view, tag, child.expression))
    } else if (t.isJSXText(child) && child.value.trim()) {
      throw new Error(`Text children are not supported in Apple native JSX <${tag}>; use a UILabel text prop.`)
    }
  }

  statements.push(t.returnStatement(view))
  return t.callExpression(t.arrowFunctionExpression([], t.blockStatement(statements)), [])
}

function applyAttribute(statements, view, tag, name, value) {
  if (name === 'children') return
  if (tag === 'UIButton' && name === 'title') {
    statements.push(t.expressionStatement(t.callExpression(t.memberExpression(view, t.identifier('setTitle')), [value, t.numericLiteral(0)])))
    return
  }
  if (tag === 'UIButton' && name === 'titleColor') {
    statements.push(t.expressionStatement(t.callExpression(t.memberExpression(view, t.identifier('setTitleColor')), [value, t.numericLiteral(0)])))
    return
  }
  if (tag === 'UISwitch' && name === 'on') {
    statements.push(t.expressionStatement(t.callExpression(t.memberExpression(view, t.identifier('setOn')), [value, t.booleanLiteral(false)])))
    return
  }
  if (name === 'layer' && t.isObjectExpression(value)) {
    for (const property of value.properties) {
      if (!t.isObjectProperty(property)) throw new Error('Only plain layer object properties are supported in Apple native JSX.')
      const key = objectPropertyName(property.key)
      statements.push(
        t.expressionStatement(
          t.assignmentExpression(
            '=',
            t.memberExpression(t.memberExpression(view, t.identifier('layer')), t.identifier(key)),
            property.value
          )
        )
      )
    }
    return
  }
  statements.push(
    t.expressionStatement(
      t.assignmentExpression('=', t.memberExpression(view, t.identifier(name)), value)
    )
  )
}

function addSubviewStatement(view, parentTag, child) {
  if (arrangedSubviewTags.has(parentTag)) {
    return t.expressionStatement(t.callExpression(t.memberExpression(view, t.identifier('addArrangedSubview')), [child]))
  }
  if (parentTag === 'UIVisualEffectView') {
    return t.expressionStatement(
      t.callExpression(t.memberExpression(t.memberExpression(view, t.identifier('contentView')), t.identifier('addSubview')), [child])
    )
  }
  return t.expressionStatement(t.callExpression(t.memberExpression(view, t.identifier('addSubview')), [child]))
}

function jsxTagName(name) {
  if (t.isJSXIdentifier(name)) return name.name
  throw new Error('Only simple Apple native JSX tag names are supported.')
}

function jsxAttributeValue(value) {
  if (!value) return t.booleanLiteral(true)
  if (t.isStringLiteral(value)) return value
  if (t.isJSXExpressionContainer(value) && !t.isJSXEmptyExpression(value.expression)) return value.expression
  throw new Error('Unsupported Apple native JSX attribute value.')
}

function objectPropertyName(key) {
  if (t.isIdentifier(key)) return key.name
  if (t.isStringLiteral(key)) return key.value
  throw new Error('Only identifier and string layer property names are supported in Apple native JSX.')
}

export function geaEmptyIrPlugin() {
  return {
    name: 'gea-empty-ir',
    closeBundle() {
      if (!process.env.GEA_IR_OUT) return
      mkdirSync(dirname(process.env.GEA_IR_OUT), { recursive: true })
      writeFileSync(
        process.env.GEA_IR_OUT,
        `${JSON.stringify(
          {
            schema: 'gea-ir',
            version: 1,
            entry: 'index.ts',
            modules: [],
            components: [],
            stores: [],
            hostCapabilities: [],
          },
          null,
          2
        )}\n`
      )
    },
  }
}

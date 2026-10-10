import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

if (process.platform !== 'darwin') {
  console.log('SKIP: native text painting requires AppKit')
  process.exit(0)
}

const renderer = readFileSync(new URL('../main/macos_renderer.mm', import.meta.url), 'utf8')
const start = renderer.indexOf('@interface GeaTextCell')
const end = renderer.indexOf('// Editable text field', start)
assert.ok(start >= 0 && end > start)
const source = `
#import <AppKit/AppKit.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
${renderer.slice(start, end)}
${readFileSync(new URL('./text-box.mm', import.meta.url), 'utf8')}
`
const executable = new URL('../../../dist/text-box-test', import.meta.url).pathname
execFileSync('clang++', ['-std=c++20', '-fobjc-arc', '-x', 'objective-c++', '-', '-framework', 'AppKit', '-o', executable], {
  input: source, stdio: ['pipe', 'inherit', 'inherit'],
})
execFileSync(executable, [], { stdio: 'inherit' })

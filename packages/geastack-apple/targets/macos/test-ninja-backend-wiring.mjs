import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
const script = readFileSync(scriptPath, 'utf8')

assert.match(
  script,
  /if command -v ninja[^]*MACOS_GENERATOR="Ninja"[^]*MACOS_GENERATOR="Shell"/,
  'macOS builds should prefer Ninja and fall back to the Shell scheduler',
)
assert.match(
  script,
  /GEA_MACOS_GENERATOR must be 'Ninja' or 'Shell'/,
  'the generator override should reject unsupported values',
)
assert.match(
  script,
  /write_content_stable_file "\$ninja_file" "\$ninja_tmp"/,
  'build.ninja should retain its timestamp when its contents do not change',
)
assert.match(
  script,
  /compile_schedule=[^]*order-compile-edges\.mjs[^]*printf 'schedule=%s\\t%s\\t%s\\n'[^]*cmp -s "\$ninja_inputs_tmp" "\$ninja_inputs_file"[^]*return/,
  'source sizes and compile-edge order should participate in graph-cache validity',
)
assert.match(
  script,
  /OBJ_FILES\+=\("\$OBJ_PATH_RESULT"\)[^]*compile_schedule=[^]*order-compile-edges\.mjs[^]*while IFS=\$'\\t' read -r source_kind source_size src/,
  'Ninja should schedule edges separately from the original object/link order',
)
assert.match(
  script,
  /write_content_stable_file "\$destination" "\$temporary"/,
  'response and signature files should be content-stable inputs',
)
assert.doesNotMatch(script, /touch -t 200001010000/, 'new dependency metadata must not be backdated past existing objects')

for (const rule of ['compile_c', 'compile_cxx', 'compile_mm']) {
  const ruleBody = script.match(new RegExp(`printf 'rule ${rule}\\\\n'([^]*?)(?=printf 'rule |local src)`))?.[1] ?? ''
  assert.match(ruleBody, /-MMD -MP -MF/, `${rule} should emit a compiler depfile`)
  assert.match(ruleBody, /printf '  depfile = \$\{out\}\.d/, `${rule} should give Ninja the depfile`)
  assert.match(ruleBody, /printf '  deps = gcc/, `${rule} should use Ninja's gcc dependency database`)
  assert.doesNotMatch(ruleBody, /generator = 1/, `${rule} must rebuild when its command changes`)
}

assert.match(
  script,
  /if \[\[ ! -f "\$BUILD_DIR\/\.ninja_deps" \]\][^]*one-time rebuild/,
  'existing Shell objects should be rebuilt once to populate safe Ninja dependency metadata',
)
assert.doesNotMatch(script, /use_ninja_deps_db=0/, 'Ninja migration must not remain permanently on loose depfiles')

assert.match(
  script,
  /write_ninja_compile_edge "\$obj" compile_cxx[^\n]*"\$pch"/,
  'generated C++ objects should carry the runtime PCH as an implicit dependency',
)
assert.match(
  script,
  /write_ninja_compile_edge "\$obj" compile_mm[^\n]*"\$pch"/,
  'generated Objective-C++ objects should carry the runtime PCH as an implicit dependency',
)
assert.match(
  script,
  /ninja -C "\$BUILD_DIR"[^\n]*-d keepdepfile/,
  'Ninja should retain depfiles so the Shell fallback can reuse its objects',
)
assert.match(
  script,
  /NINJA_DEPS_INVALIDATED[^]*rm -f "\$BUILD_DIR\/\.ninja_deps"/,
  'a Shell recompile should invalidate Ninja dependency metadata before switching back',
)
assert.match(
  script,
  /GEA_MACOS_NINJA_DRY_RUN[^]*ninja -C "\$BUILD_DIR"[^\n]* -n /,
  'the backend should support validating its object graph without compiling it',
)
assert.match(
  script,
  /if \[\[ "\$MACOS_GENERATOR" == "Ninja" \]\][^]*compile_with_ninja[^]*else[^]*queue_compile/,
  'the original Shell compile queue should remain available as a fallback',
)

console.log('macOS Ninja backend wiring tests passed')

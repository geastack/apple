import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const scriptPath = fileURLToPath(new URL('./build-macos.sh', import.meta.url))
const script = readFileSync(scriptPath, 'utf8')

assert.match(
  script,
  /GEA_MACOS_HARD_MUTE_GATE and GEA_MACOS_HARD_MUTE_SOURCE must be set together/,
  'partial hard-mute configuration must fail before the build starts',
)
assert.match(
  script,
  /timing_mark codesign[^]*preflight-hard-muted-artifact\.mjs" record[^]*preflight-hard-muted-artifact\.mjs" verify[^]*timing_mark hard-mute-preflight/,
  'recording and verification must happen after code signing and before the build reports a runnable artifact',
)
assert.match(
  script,
  /record[^]*--executable "\$LINK_OUTPUT"[^]*--link-signature "\$LINK_SIGNATURE_FILE"[^]*--source "\$MACOS_HARD_MUTE_SOURCE"[^]*--gate "\$MACOS_HARD_MUTE_GATE"/,
  'the provenance record must bind the selected source, linked executable, link signature, and configured gate',
)
assert.match(
  script,
  /--dependency-root "\$ROOT_DIR"[^]*--dependency-root "\$GEA_COMPILER"[^]*--dependency-root "\$GEA_CORE"[^]*--dependency-root "\$BUILD_INVOCATION_CWD"/,
  'the build must freeze Apple, compiler, core, and app dependency revisions',
)
assert.match(
  script,
  /verify[^]*--manifest "\$HARD_MUTE_PROVENANCE_FILE"[^]*--executable "\$LINK_OUTPUT"[^]*--source "\$MACOS_HARD_MUTE_SOURCE"[^]*--gate "\$MACOS_HARD_MUTE_GATE"/,
  'the verifier must require the operator-selected executable, source, and gate instead of trusting only manifest contents',
)
assert.ok(
  script.indexOf('preflight-hard-muted-artifact.mjs" verify') < script.indexOf('echo "Built $APP_BUNDLE"'),
  'a hard-muted build must not be reported as runnable before the preflight succeeds',
)

console.log('native hard-mute artifact preflight wiring tests passed')

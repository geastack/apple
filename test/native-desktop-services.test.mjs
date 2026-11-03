import assert from 'node:assert/strict'
import { readFileSync, writeFileSync } from 'node:fs'
import { basename, dirname, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { execFileSync } from 'node:child_process'
import {
  appleSdkFixture,
  generateAppleDeclarations,
  generateAppleRuntimeModules,
  generateAppleBridgeMetadata
} from '../packages/geastack-apple/dist/index.js'
import { appleNativePlugin } from '../packages/geatsc-plugin-apple-native/dist/index.js'

const root = resolve(import.meta.dirname, '../packages/geastack-apple')
for (const [name, text] of Object.entries(generateAppleDeclarations(appleSdkFixture))) {
  writeFileSync(`${root}/generated/${basename(name)}.d.ts`, text)
}
for (const [name, text] of Object.entries(generateAppleRuntimeModules(appleSdkFixture))) {
  writeFileSync(`${root}/runtime/${basename(name)}.js`, text)
}
const names = new Set(['Foundation', 'Dispatch', 'AppKit', 'Security', 'UserNotifications', 'EventKit'])
const fixture = {
  frameworks: appleSdkFixture.frameworks.filter((framework) => names.has(framework.name))
}
const metadata = generateAppleBridgeMetadata(fixture)
assert.ok(metadata.functions['Foundation.randomUUID'])
assert.ok(metadata.functions['UserNotifications.scheduleNotification'].bridgeBody)
const eventKit = appleSdkFixture.frameworks.find((framework) => framework.name === 'EventKit')
for (const fn of eventKit.functions) assert.ok(metadata.functions[`EventKit.${fn.name}`].bridgeBody, `EventKit.${fn.name} has a bridge body`)
assert.match(readFileSync(`${root}/generated/EventKit.d.ts`, 'utf8'), /export declare function events\(startISO: string, endISO: string, calendarIdsJSON: string\): string/)
assert.match(readFileSync(`${root}/runtime/EventKit.js`, 'utf8'), /export function watchChanges\(\)/)
const out = `${root}/dist`
appleNativePlugin({ metadata }).createCppBackend({ outDir: out }).transformGeneratedSources([])
const source = `
#include "gea/apple/native_bridge.h"
#import <Foundation/Foundation.h>
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <string>
int main(int argc, char **argv) {
  @autoreleasepool {
    using namespace gea::apple::Foundation;
    const auto first = randomUUID();
    assert(first.size() == 36 && first != randomUUID());
    assert(!localTimeZone().empty());
    const std::string path = std::string(argv[1]) + "/native-services-test.txt";
    bool changed = false;
    const auto watch = watchPath(argv[1], [&]() { changed = true; });
    writeTextFile(path, "first");
    assert(readTextFile(path) == "first");
    writeTextFile(path, "replacement");
    assert(readTextFile(path) == "replacement");
    bool fileChanged = false;
    const auto fileWatch = watchPath(path, [&]() { fileChanged = true; });
    FILE *file = std::fopen(path.c_str(), "w");
    assert(file);
    std::fputs("in-place", file);
    std::fclose(file);
    const auto deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ((!changed || !fileChanged) && [deadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(changed && fileChanged);
    assert(readTextFile(path) == "in-place");
    stopWatchingPath(fileWatch);
    stopWatchingPath(watch);
    stopWatchingPath(watch);
    std::remove(path.c_str());
    bool invalid = false;
    gea::apple::UserNotifications::scheduleNotification("test", "", "", -1, [&](std::string error) { invalid = !error.empty(); });
    assert(invalid);
    // Calendar access needs a TCC grant, so only behavior that holds without it is checked.
    using namespace gea::apple::EventKit;
    const auto status = authorizationStatus();
    assert(status == "notDetermined" || status == "restricted" || status == "denied" || status == "fullAccess" || status == "writeOnly");
    if (status != "fullAccess") assert(calendars() == "[]");
    bool badRange = false;
    try { events("not a date", "2026-01-02T00:00:00Z", ""); } catch (const std::runtime_error &) { badRange = true; }
    assert(badRange);
    std::string spanError, removeError;
    saveEvent("{}", "everything", [&](std::string, std::string error) { spanError = error; });
    removeEvent("missing", "", "thisEvent", [&](std::string error) { removeError = error; });
    const auto eventWatch = watchChanges([]() {});
    stopWatchingChanges(eventWatch);
    stopWatchingChanges(eventWatch);
    const auto callbackDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while ((spanError.empty() || removeError.empty()) && [callbackDeadline timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(spanError == "span must be thisEvent or futureEvents");
    assert(!removeError.empty());
    std::printf("EventKit authorization status: %s\\n", status.c_str());
    std::puts("native desktop services passed");
  }
}
`
const executable = `${out}/native-desktop-services-test`
execFileSync(
  'clang++',
  [
    '-std=c++20',
    '-fobjc-arc',
    `-I${out}`,
    `${out}/gea/apple/native_bridge.mm`,
    '-x',
    'objective-c++',
    '-',
    '-framework',
    'Foundation',
    '-framework',
    'AppKit',
    '-framework',
    'Security',
    '-framework',
    'UserNotifications',
    '-framework',
    'EventKit',
    '-framework',
    'CoreGraphics',
    '-o',
    executable
  ],
  { input: source, stdio: ['pipe', 'inherit', 'inherit'] }
)
process.stdout.write(execFileSync(executable, [out], { encoding: 'utf8' }))

// Exercise the declarations through the production compiler and the same bridge.
const requireFromApple = createRequire(`${root}/package.json`)
const packageRoot = (name) => dirname(requireFromApple.resolve(`@geastack/${name}/package.json`))
const compiler = packageRoot('compiler')
execFileSync(
  process.execPath,
  [
    `${compiler}/dist/cli.js`,
    'compile',
    '--out-dir',
    out,
    '--project',
    resolve(import.meta.dirname, 'native-desktop-service-bindings.tsconfig.json'),
    resolve(import.meta.dirname, 'native-desktop-service-bindings.ts')
  ],
  {
    encoding: 'utf8',
    env: {
      ...process.env,
      GEATSC2_APPLE_SDK: '@geastack/apple',
      GEATSC2_APPLE_PLUGIN: resolve(import.meta.dirname, '../packages/geatsc-plugin-apple-native/dist/index.js')
    }
  }
)
const units = readFileSync(`${out}/geatsc-sources.txt`, 'utf8').trim().split('\n')
const emitted = units.map((path) => readFileSync(path, 'utf8')).join('\n')
assert.ok(emitted.includes('gea::apple::Foundation::randomUUID'))
assert.ok(emitted.includes('gea::apple::EventKit::events'))
const includes = [
  `${packageRoot('core')}/include`, `${packageRoot('host')}/include`,
  packageRoot('engine'), `${packageRoot('engine')}/ui`,
  packageRoot('elements'), `${packageRoot('elements')}/ui`
].map((path) => `-I${path}`)
execFileSync(
  'clang++',
  [
    '-std=c++20',
    '-fobjc-arc',
    '-fsyntax-only',
    `-I${out}`,
    `-I${compiler}/src/targets/cpp/runtime`,
    ...includes,
    '-x',
    'objective-c++',
    '-'
  ],
  { input: emitted, stdio: ['pipe', 'inherit', 'inherit'] }
)
console.log('native desktop TypeScript bindings compiled')

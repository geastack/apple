function geaAppleSwiftDataNativeOnly(name) {
  throw new Error(`@geajs/apple/SwiftData ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export function openModelContainer() {
  return geaAppleSwiftDataNativeOnly("openModelContainer")
}

export function mainModelContext() {
  return geaAppleSwiftDataNativeOnly("mainModelContext")
}

export function insertModelJSON() {
  return geaAppleSwiftDataNativeOnly("insertModelJSON")
}

export function saveModelContext() {
  return geaAppleSwiftDataNativeOnly("saveModelContext")
}

export function fetchModelsJSON() {
  return geaAppleSwiftDataNativeOnly("fetchModelsJSON")
}

export class ModelContainer {
}

export class ModelContext {
}

# @geastack/geatsc-plugin-apple-native

The Apple-native binding plugin for `geatsc`, the GeaStack TypeScript-to-C++
compiler. It reads the Apple SDK binding metadata published by
`@geastack/apple` and gives the compiler the host shims that let calls on
`UIView`, `MKMapView`, `MTKView` and the other bound classes compile to
Objective-C++ thunks.

```sh
npm install @geastack/geatsc-plugin-apple-native
```

## How it is loaded

`@geastack/core`'s build driver adds the plugin automatically when an app is
built for an Apple target. It first generates `gea-apple-metadata.json` into
the build output from the bindings the app uses, then passes that file as the
`apple.metadata` plugin option. By hand:

```sh
geatsc compile-module-graph gea-module-graph.json --entry src/index.tsx \
  --plugin @geastack/geatsc-plugin-apple-native \
  --plugin-option apple.metadata=dist/gea-apple-metadata.json
```

`appleNativePlugin(options)` returns the `geatsc` plugin;
`createAppleHostShims(metadata)` builds the host shim table on its own for
tools that need it without the plugin. Objective-C-only types are guarded so
that plain C++ translation units never see them.

## License

Apache-2.0. See `LICENSE`.

#import <AppKit/AppKit.h>
#include "image.h"
#include "pixel.h"
#include "ui/tree_internal.h"
#include "../main/image_bridge.h"
#include "../main/color_convert.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>

int main()
{
  using namespace gea::framework::graphics;
  static_assert(sizeof(pixel::native_t) == 4, "Desktop must use RGBA8888");
  @autoreleasepool {
    // Every channel exercises all 256 values, including values RGB565 loses.
    unsigned char expected[256 * 4];
    for (int i = 0; i < 256; ++i) {
      expected[i * 4] = i;
      expected[i * 4 + 1] = 255 - i;
      expected[i * 4 + 2] = (i * 73) % 256;
      expected[i * 4 + 3] = i;
    }
    NSBitmapImageRep *source = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL pixelsWide:256 pixelsHigh:1
      bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
      colorSpaceName:NSDeviceRGBColorSpace
      bitmapFormat:NSBitmapFormatAlphaNonpremultiplied bytesPerRow:1024 bitsPerPixel:32];
    std::memcpy(source.bitmapData, expected, sizeof(expected));
    NSData *png = [source representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    auto &store = ImageStore::instance();
    const int id = store.decode(static_cast<const unsigned char *>(png.bytes), png.length, -1);
    assert(id >= 0);
    const auto *pixels = store.currentPixels(id);
    for (int i = 0; i < 256; ++i) {
      int r, g, b, a;
      pixel::unpackNative8(pixels[i], &r, &g, &b, &a);
      assert(r == expected[i * 4] && g == expected[i * 4 + 1]);
      assert(b == expected[i * 4 + 2] && a == expected[i * 4 + 3]);
      NSColor *color = gea::macos::nativeToNSColor(pixels[i]);
      assert(std::lround(color.redComponent * 255) == r);
      assert(std::lround(color.greenComponent * 255) == g);
      assert(std::lround(color.blueComponent * 255) == b);
    }
    NSImage *image = gea::macos::imageForId(id);
    assert(image);
    NSBitmapImageRep *result = (NSBitmapImageRep *)image.representations.firstObject;
    assert(std::memcmp(result.bitmapData, expected, sizeof(expected)) == 0);
    NSImage *region = gea::macos::imageForIdRegion(id, 17, 0, 8, 1);
    assert(region);
    NSBitmapImageRep *cropped = (NSBitmapImageRep *)region.representations.firstObject;
    assert(cropped.pixelsWide == 8 && cropped.pixelsHigh == 1);
    assert(std::memcmp(cropped.bitmapData, expected + 17 * 4, 8 * 4) == 0);
    assert(gea::macos::imageForIdRegion(id, 250, 0, 8, 1) == nil);
    NSImage *cover = gea::macos::imageForIdCover(id, 64, 1);
    assert(cover);
    NSBitmapImageRep *covered = (NSBitmapImageRep *)cover.representations.firstObject;
    assert(covered.pixelsWide == 64 && covered.pixelsHigh == 1);
    assert(std::memcmp(covered.bitmapData, expected + 96 * 4, 64 * 4) == 0);
    auto &tree = gea::embedded::ui::Tree::instance();
    const int node = tree.createImage();
    tree.setStyle(node, gea::embedded::ui::Property::ImageId, id);
    NSImage *ordinaryNode = gea::macos::imageForNode(node);
    assert(ordinaryNode); // absent attributes are empty strings, not crop requests
    NSBitmapImageRep *ordinary = (NSBitmapImageRep *)ordinaryNode.representations.firstObject;
    assert(ordinary.pixelsWide == 256);
    tree.setAttribute(node, "data-source-x", "17");
    tree.setAttribute(node, "data-source-y", "0");
    tree.setAttribute(node, "data-source-width", "8");
    tree.setAttribute(node, "data-source-height", "1");
    NSImage *slicedNode = gea::macos::imageForNode(node);
    assert(slicedNode);
    NSBitmapImageRep *sliced = (NSBitmapImageRep *)slicedNode.representations.firstObject;
    assert(sliced.pixelsWide == 8);
    assert(std::memcmp(sliced.bitmapData, expected + 17 * 4, 8 * 4) == 0);
    tree.removeAttribute(node, "data-source-width");
    assert(gea::macos::imageForNode(node));
    static_assert(kImageMax >= 200, "Desktop image capacity must cover complex sliced screens");
    int extra[200];
    for (int &slot : extra) { slot = store.decode(static_cast<const unsigned char *>(png.bytes), png.length, -1); assert(slot >= 0); assert(gea::macos::imageForId(slot)); }
    for (int slot : extra) store.dispose(slot);
    store.dispose(id);
    std::puts("PASS: PNG decode and AppKit bridge preserve all 256 RGBA channel values exactly");
  }
}

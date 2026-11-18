#import "canvas_view.h"

#include "canvas.h"
#include "pixel.h"
#include "ui/tree_internal.h"

#include <dispatch/dispatch.h>
#import <IOSurface/IOSurfaceRef.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <TargetConditionals.h>
#include <unistd.h>

#include <algorithm>
#include <mutex>
#include <vector>

namespace {

// A frame's pixels are handed to Core Animation inside a CGImage, which may
// still be reading one after the next frame starts: each frame takes a buffer
// from this pool and the image's release returns it. A fresh allocation per
// frame instead page-faults the whole buffer in again every time.
struct FrameBuffer {
	std::uint8_t *bytes;
	std::size_t size;
};
std::mutex gFramePoolLock;
std::vector<FrameBuffer> gFramePool;

void releaseFrame(void *, const void *data, std::size_t size)
{
	std::lock_guard<std::mutex> lock(gFramePoolLock);
	gFramePool.push_back({static_cast<std::uint8_t *>(const_cast<void *>(data)), size});
}

std::uint8_t *takeFrame(std::size_t size)
{
	{
		std::lock_guard<std::mutex> lock(gFramePoolLock);
		while (!gFramePool.empty()) {
			const FrameBuffer buffer = gFramePool.back();
			gFramePool.pop_back();
			if (buffer.size == size) return buffer.bytes;
			std::free(buffer.bytes);  // the canvas was resized
		}
	}
	return static_cast<std::uint8_t *>(std::malloc(size));
}

#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
// Draws the canvas texture over the whole drawable, opaque.
NSString *const kPresentShader = @R"(
#include <metal_stdlib>
using namespace metal;
struct Corner { float4 position [[position]]; float2 uv; };
vertex Corner canvasVertex(uint id [[vertex_id]]) {
	const float2 uv = float2((id << 1) & 2, id & 2);
	Corner corner;
	corner.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
	corner.uv = uv;
	return corner;
}
fragment half4 canvasFragment(Corner in [[stage_in]], texture2d<half> canvas [[texture(0)]]) {
	constexpr sampler nearest(filter::nearest);
	return half4(canvas.sample(nearest, in.uv).rgb, 1.0h);
}
)";

struct GpuPresenter {
	id<MTLDevice> device;
	id<MTLCommandQueue> queue;
	id<MTLRenderPipelineState> pipeline;
};

// The shared Metal state, or nullptr where there is no usable GPU.
GpuPresenter *gpuPresenter()
{
	static GpuPresenter *presenter = []() -> GpuPresenter * {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device) return nullptr;
		NSError *error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:kPresentShader options:nil error:&error];
		if (!library) return nullptr;
		MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
		descriptor.vertexFunction = [library newFunctionWithName:@"canvasVertex"];
		descriptor.fragmentFunction = [library newFunctionWithName:@"canvasFragment"];
		descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
		id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!pipeline || !queue) return nullptr;
		return new GpuPresenter{device, queue, pipeline};
	}();
	return presenter;
}

IOSurfaceRef createSurface(int w, int h)
{
	NSDictionary *properties = @{
		(id)kIOSurfaceWidth: @(w),
		(id)kIOSurfaceHeight: @(h),
		(id)kIOSurfaceBytesPerElement: @4,
		(id)kIOSurfacePixelFormat: @(static_cast<std::uint32_t>('BGRA')),
	};
	return IOSurfaceCreate((__bridge CFDictionaryRef)properties);
}

// RGBA8888 rows into an opaque BGRA surface, sliced across every core.
void copyToSurface(const std::uint32_t *src, int w, int h, IOSurfaceRef surface)
{
	auto *base = static_cast<std::uint8_t *>(IOSurfaceGetBaseAddress(surface));
	const std::size_t stride = IOSurfaceGetBytesPerRow(surface);
	constexpr int kRowsPerSlice = 64;
	const int slices = (h + kRowsPerSlice - 1) / kRowsPerSlice;
	dispatch_apply(static_cast<size_t>(slices), dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^(size_t slice) {
		const int y0 = static_cast<int>(slice) * kRowsPerSlice;
		const int y1 = std::min(h, y0 + kRowsPerSlice);
		for (int y = y0; y < y1; ++y) {
			const std::uint32_t *in = src + static_cast<std::size_t>(y) * w;
			auto *out = reinterpret_cast<std::uint32_t *>(base + static_cast<std::size_t>(y) * stride);
			for (int x = 0; x < w; ++x) {
				const std::uint32_t p = in[x];  // bytes R,G,B,A -> B,G,R,A (little-endian words)
				out[x] = (p & 0x0000FF00u) | ((p & 0xFFu) << 16) | ((p >> 16) & 0xFFu) | 0xFF000000u;
			}
		}
	});
}
#endif

}  // namespace

@interface GeaCanvasView ()
#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
// Surfaces handed to Core Animation, reused once the render server is done
// with them. The render server reads an IOSurface in place, in the GPU's own
// BGRA format; a CGImage is converted and uploaded anew every frame.
@property(nonatomic, strong) NSMutableArray *surfaces;
// The GPU path: the canvas buffer wrapped as a texture (no copy) and drawn
// into a Metal layer's drawable.
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@property(nonatomic, strong) id<MTLTexture> canvasTexture;
@property(nonatomic, assign) const void *texturePixels;
#endif
@end

@implementation GeaCanvasView

- (instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_nodeId = -1;
		self.opaque = NO;
		self.backgroundColor = UIColor.clearColor;
		self.userInteractionEnabled = NO;
	}
	return self;
}

// Sets the canvas pixels as the layer's contents, so the GPU scales and
// composites them. Drawing them in drawRect instead pushes every pixel through
// CoreGraphics on the CPU, which for a 4K canvas takes longer than the app's
// whole frame.
- (void)present
{
	if (self.nodeId < 0) return;
	auto &tree = gea::embedded::ui::Tree::instance();
	if (self.nodeId >= tree.nodeCount()) return;
	const auto *canvas = gea::embedded::ui::Tree::instance().canvas(self.nodeId);
	if (!canvas) return;
	const gea::framework::graphics::pixel::native_t *src = canvas->pixels();
	const int w = canvas->width();
	const int h = canvas->height();
	if (!src || w <= 0 || h <= 0) return;

#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
	if ([self presentOnGpu:src width:w height:h]) return;
	{
		if (!self.surfaces) self.surfaces = [NSMutableArray array];
		IOSurfaceRef surface = nullptr;
		const id shown = self.layer.contents;
		for (id candidate in self.surfaces) {
			IOSurfaceRef s = (__bridge IOSurfaceRef)candidate;
			if (static_cast<int>(IOSurfaceGetWidth(s)) != w || static_cast<int>(IOSurfaceGetHeight(s)) != h) continue;
			if (candidate == shown || IOSurfaceIsInUse(s)) continue;
			surface = s;
			break;
		}
		if (!surface && self.surfaces.count < 4) {
			IOSurfaceRef created = createSurface(w, h);
			if (created) {
				[self.surfaces addObject:(__bridge_transfer id)created];
				surface = created;
			}
		}
		if (surface && IOSurfaceLock(surface, 0, nullptr) == 0) {
			copyToSurface(reinterpret_cast<const std::uint32_t *>(src), w, h, surface);
			IOSurfaceUnlock(surface, 0, nullptr);
			// No implicit animation: a contents change would otherwise cross-fade.
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			self.layer.contentsGravity = kCAGravityResize;
			self.layer.contents = (__bridge id)surface;
			[CATransaction commit];
			return;
		}
	}
#endif
	const std::size_t bytes = static_cast<std::size_t>(w) * h * 4;
	auto *dst = takeFrame(bytes);
	if (!dst) return;
#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
	// native_t is already RGBA8888 (R,G,B,A bytes per pixel) — exactly the
	// CGImage's RGBX layout — so present it straight through. One core cannot
	// saturate memory bandwidth: a large canvas copies in slices on every core.
	constexpr std::size_t kSlice = 4u << 20;
	if (bytes >= 2 * kSlice) {
		const std::size_t slices = (bytes + kSlice - 1) / kSlice;
		const auto *from = reinterpret_cast<const std::uint8_t *>(src);
		dispatch_apply(slices, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^(size_t i) {
			const std::size_t offset = i * kSlice;
			std::memcpy(dst + offset, from + offset, std::min(kSlice, bytes - offset));
		});
	} else {
		std::memcpy(dst, src, bytes);
	}
#else
	for (int i = 0; i < w * h; i++) {
		int r, g, b;
		gea::framework::graphics::pixel::unpackRgb565(src[i], &r, &g, &b);
		dst[i * 4 + 0] = static_cast<std::uint8_t>((r * 255 + 15) / 31);
		dst[i * 4 + 1] = static_cast<std::uint8_t>((g * 255 + 31) / 63);
		dst[i * 4 + 2] = static_cast<std::uint8_t>((b * 255 + 15) / 31);
		dst[i * 4 + 3] = 0xFF;
	}
#endif

	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, dst, bytes, releaseFrame);
	const uint32_t bitmapInfo = static_cast<uint32_t>(kCGImageAlphaNoneSkipLast) |
	                            static_cast<uint32_t>(kCGBitmapByteOrder32Big);
	CGImageRef image = CGImageCreate(static_cast<std::size_t>(w),
	                                 static_cast<std::size_t>(h),
	                                 8,
	                                 32,
	                                 static_cast<std::size_t>(w) * 4,
	                                 cs,
	                                 bitmapInfo,
	                                 provider,
	                                 nullptr,
	                                 false,
	                                 kCGRenderingIntentDefault);
	if (image) {
		// No implicit animation: a contents change would otherwise cross-fade.
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		self.layer.contentsGravity = kCAGravityResize;
		self.layer.contents = (__bridge id)image;
		[CATransaction commit];
		CGImageRelease(image);
	}
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(cs);
}

#if GEA_EMBEDDED_PIXEL_FORMAT == GEA_PIXEL_RGBA8888
// The GPU reads the canvas buffer where it lies (the canvas store allocates it
// in whole pages on Apple hosts) and writes the drawable: the CPU copies
// nothing. Returns NO where the buffer cannot be wrapped, for the copy paths.
- (BOOL)presentOnGpu:(const void *)src width:(int)w height:(int)h
{
#if TARGET_OS_SIMULATOR
	// The simulator's Metal driver cannot wrap app memory (it traps): copy.
	(void)src;
	(void)w;
	(void)h;
	return NO;
#else
	GpuPresenter *gpu = gpuPresenter();
	if (!gpu) return NO;
	const std::size_t page = static_cast<std::size_t>(getpagesize());
	const std::size_t rowBytes = static_cast<std::size_t>(w) * 4;
	if (reinterpret_cast<std::uintptr_t>(src) % page != 0) return NO;
	if (rowBytes % [gpu->device minimumLinearTextureAlignmentForPixelFormat:MTLPixelFormatRGBA8Unorm] != 0) return NO;

	if (src != self.texturePixels || !self.canvasTexture || static_cast<int>(self.canvasTexture.width) != w ||
	    static_cast<int>(self.canvasTexture.height) != h) {
		self.canvasTexture = nil;
		self.texturePixels = nullptr;
		const std::size_t bytes = (rowBytes * h + page - 1) & ~(page - 1);
		id<MTLBuffer> buffer = [gpu->device newBufferWithBytesNoCopy:const_cast<void *>(src)
		                                                      length:bytes
		                                                     options:MTLResourceStorageModeShared
		                                                 deallocator:nil];
		if (!buffer) return NO;
		MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
		                                                                                      width:w
		                                                                                     height:h
		                                                                                  mipmapped:NO];
		descriptor.storageMode = MTLStorageModeShared;
		descriptor.usage = MTLTextureUsageShaderRead;
		self.canvasTexture = [buffer newTextureWithDescriptor:descriptor offset:0 bytesPerRow:rowBytes];
		if (!self.canvasTexture) return NO;
		self.texturePixels = src;
	}

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	if (!self.metalLayer) {
		CAMetalLayer *layer = [CAMetalLayer layer];
		layer.device = gpu->device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.framebufferOnly = YES;
		layer.opaque = YES;
		[self.layer addSublayer:layer];
		self.metalLayer = layer;
		self.layer.contents = nil;
	}
	if (!CGRectEqualToRect(self.metalLayer.frame, self.bounds)) self.metalLayer.frame = self.bounds;
	const CGSize size = CGSizeMake(w, h);
	if (!CGSizeEqualToSize(self.metalLayer.drawableSize, size)) self.metalLayer.drawableSize = size;
	[CATransaction commit];

	id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
	if (!drawable) return YES;  // none free this frame: skip it
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = drawable.texture;
	pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	id<MTLCommandBuffer> commands = [gpu->queue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
	[encoder setRenderPipelineState:gpu->pipeline];
	[encoder setFragmentTexture:self.canvasTexture atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
	[encoder endEncoding];
	[commands presentDrawable:drawable];
	[commands commit];
	// The app draws into this same buffer next frame: wait out the GPU's read.
	[commands waitUntilCompleted];
	return YES;
#endif
}
#endif

@end

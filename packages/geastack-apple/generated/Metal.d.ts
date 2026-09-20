export declare const MTLPixelFormatInvalid: number
export declare const MTLPixelFormatBGRA8Unorm_sRGB: number
export declare const MTLPixelFormatDepth32Float: number
export declare const MTLPrimitiveTypeTriangle: number
export declare const MTLResourceStorageModeShared: number
export declare const MTLCompareFunctionLess: number

export declare function MTLCreateSystemDefaultDevice(): MTLDevice | null
export declare function MTLClearColorMake(red: number, green: number, blue: number, alpha: number): MTLClearColor

export interface MTLClearColor {
  red: number
  green: number
  blue: number
  alpha: number
}

export declare class MTLCompileOptions {
  constructor()
}

export declare class MTLDevice {
  newCommandQueue(): MTLCommandQueue | null
  newLibraryWithSourceOptionsError(source: string, options: MTLCompileOptions): MTLLibrary | null
  newBufferWithBytesLengthOptions(bytes: number[], length: number, options: number): MTLBuffer | null
  newRenderPipelineStateWithDescriptorError(descriptor: MTLRenderPipelineDescriptor): MTLRenderPipelineState | null
  newDepthStencilStateWithDescriptor(descriptor: MTLDepthStencilDescriptor): MTLDepthStencilState | null
}

export declare class MTLCommandQueue {
  commandBuffer(): MTLCommandBuffer | null
}

export declare class MTLCommandBuffer {
  renderCommandEncoderWithDescriptor(descriptor: MTLRenderPassDescriptor): MTLRenderCommandEncoder | null
  presentDrawable(drawable: MTLDrawable): void
  commit(): void
}

export declare class MTLLibrary {
  newFunctionWithName(name: string): MTLFunction | null
}

export declare class MTLFunction {
}

export declare class MTLRenderPipelineDescriptor {
  constructor()
  vertexFunction: MTLFunction | null
  fragmentFunction: MTLFunction | null
  readonly colorAttachments: MTLRenderPipelineColorAttachmentDescriptorArray
  depthAttachmentPixelFormat: number
}

export declare class MTLRenderPipelineColorAttachmentDescriptorArray {
  objectAtIndexedSubscript(index: number): MTLRenderPipelineColorAttachmentDescriptor
}

export declare class MTLRenderPipelineColorAttachmentDescriptor {
  pixelFormat: number
}

export declare class MTLRenderPipelineState {
}

export declare class MTLBuffer {
}

export declare class MTLDepthStencilDescriptor {
  constructor()
  depthCompareFunction: number
  depthWriteEnabled: boolean
}

export declare class MTLDepthStencilState {
}

export declare class MTLRenderCommandEncoder {
  setRenderPipelineState(pipelineState: MTLRenderPipelineState): void
  setDepthStencilState(depthStencilState: MTLDepthStencilState): void
  setVertexBufferOffsetAtIndex(buffer: MTLBuffer, offset: number, index: number): void
  setVertexBytesLengthAtIndex(bytes: number[], length: number, index: number): void
  drawPrimitivesVertexStartVertexCount(primitiveType: number, vertexStart: number, vertexCount: number): void
  endEncoding(): void
}

export declare class MTLRenderPassDescriptor {
}

export declare class MTLDrawable {
}

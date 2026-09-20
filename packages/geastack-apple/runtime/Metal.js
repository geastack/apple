function geaAppleMetalNativeOnly(name) {
  throw new Error(`@geajs/apple/Metal ${name} is native-only and must be lowered by @geastack/geatsc-plugin-apple-native.`)
}

export const MTLPixelFormatInvalid = 0
export const MTLPixelFormatBGRA8Unorm_sRGB = 80
export const MTLPixelFormatDepth32Float = 252
export const MTLPrimitiveTypeTriangle = 3
export const MTLResourceStorageModeShared = 0
export const MTLCompareFunctionLess = 2

export function MTLCreateSystemDefaultDevice() {
  return geaAppleMetalNativeOnly("MTLCreateSystemDefaultDevice")
}

export function MTLClearColorMake() {
  return geaAppleMetalNativeOnly("MTLClearColorMake")
}

export class MTLCompileOptions {
  constructor() {
    geaAppleMetalNativeOnly("new MTLCompileOptions")
  }
}

export class MTLDevice {
  newCommandQueue() {
    return geaAppleMetalNativeOnly("MTLDevice.newCommandQueue")
  }
  newLibraryWithSourceOptionsError() {
    return geaAppleMetalNativeOnly("MTLDevice.newLibraryWithSourceOptionsError")
  }
  newBufferWithBytesLengthOptions() {
    return geaAppleMetalNativeOnly("MTLDevice.newBufferWithBytesLengthOptions")
  }
  newRenderPipelineStateWithDescriptorError() {
    return geaAppleMetalNativeOnly("MTLDevice.newRenderPipelineStateWithDescriptorError")
  }
  newDepthStencilStateWithDescriptor() {
    return geaAppleMetalNativeOnly("MTLDevice.newDepthStencilStateWithDescriptor")
  }
}

export class MTLCommandQueue {
  commandBuffer() {
    return geaAppleMetalNativeOnly("MTLCommandQueue.commandBuffer")
  }
}

export class MTLCommandBuffer {
  renderCommandEncoderWithDescriptor() {
    return geaAppleMetalNativeOnly("MTLCommandBuffer.renderCommandEncoderWithDescriptor")
  }
  presentDrawable() {
    return geaAppleMetalNativeOnly("MTLCommandBuffer.presentDrawable")
  }
  commit() {
    return geaAppleMetalNativeOnly("MTLCommandBuffer.commit")
  }
}

export class MTLLibrary {
  newFunctionWithName() {
    return geaAppleMetalNativeOnly("MTLLibrary.newFunctionWithName")
  }
}

export class MTLFunction {
}

export class MTLRenderPipelineDescriptor {
  constructor() {
    geaAppleMetalNativeOnly("new MTLRenderPipelineDescriptor")
  }
}

export class MTLRenderPipelineColorAttachmentDescriptorArray {
  objectAtIndexedSubscript() {
    return geaAppleMetalNativeOnly("MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript")
  }
}

export class MTLRenderPipelineColorAttachmentDescriptor {
}

export class MTLRenderPipelineState {
}

export class MTLBuffer {
}

export class MTLDepthStencilDescriptor {
  constructor() {
    geaAppleMetalNativeOnly("new MTLDepthStencilDescriptor")
  }
}

export class MTLDepthStencilState {
}

export class MTLRenderCommandEncoder {
  setRenderPipelineState() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.setRenderPipelineState")
  }
  setDepthStencilState() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.setDepthStencilState")
  }
  setVertexBufferOffsetAtIndex() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.setVertexBufferOffsetAtIndex")
  }
  setVertexBytesLengthAtIndex() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.setVertexBytesLengthAtIndex")
  }
  drawPrimitivesVertexStartVertexCount() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.drawPrimitivesVertexStartVertexCount")
  }
  endEncoding() {
    return geaAppleMetalNativeOnly("MTLRenderCommandEncoder.endEncoding")
  }
}

export class MTLRenderPassDescriptor {
}

export class MTLDrawable {
}

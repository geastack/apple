import type { CGSize } from '@geastack/apple/CoreGraphics'
import type { MTLDevice, MTLDrawable, MTLClearColor, MTLRenderPassDescriptor } from '@geastack/apple/Metal'
import type { UIView } from '@geastack/apple/UIKit'

export declare class MTKView extends UIView {
  constructor()
  device: MTLDevice | null
  delegate: MTKViewDelegate | null
  colorPixelFormat: number
  depthStencilPixelFormat: number
  clearColor: MTLClearColor
  preferredFramesPerSecond: number
  enableSetNeedsDisplay: boolean
  paused: boolean
  readonly drawableSize: CGSize
  readonly currentRenderPassDescriptor: MTLRenderPassDescriptor | null
  readonly currentDrawable: MTLDrawable | null
}

export declare class MTKViewDelegate {
  static create(drawInMTKView: () => void): MTKViewDelegate
}

import type { NSObject } from '@geastack/apple/Foundation'
import type { CGSize } from '@geastack/apple/CoreGraphics'

export declare class CALayer extends NSObject {
  frame: CGRect
  cornerRadius: number
  shadowOpacity: number
  shadowRadius: number
  shadowOffset: CGSize
  masksToBounds: boolean
  addSublayer(layer: CALayer): void
}

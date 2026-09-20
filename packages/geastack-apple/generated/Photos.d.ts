import type { NSData, NSObject } from '@geastack/apple/Foundation'

export declare class PHPhotoLibrary extends NSObject {
  static saveImageData(data: NSData, handler: (success: boolean, error: string) => void): void
}

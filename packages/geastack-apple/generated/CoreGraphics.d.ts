export declare function CGRectMake(x: number, y: number, width: number, height: number): CGRect
export declare function CGPointMake(x: number, y: number): CGPoint
export declare function CGSizeMake(width: number, height: number): CGSize

export interface CGPoint {
  x: number
  y: number
}

export interface CGSize {
  width: number
  height: number
}

export interface CGRect {
  origin: CGPoint
  size: CGSize
}

export declare function CMTimeMakeWithSeconds(seconds: number, preferredTimescale: number): CMTime

export interface CMTime {
  value: number
  timescale: number
  flags: number
  epoch: number
}

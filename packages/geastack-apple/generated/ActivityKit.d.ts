export declare function requestLiveActivity(attributesJSON: string, contentStateJSON: string): LiveActivityHandle
export declare function updateLiveActivity(activity: LiveActivityHandle, contentStateJSON: string): void
export declare function endLiveActivity(activity: LiveActivityHandle): void

export declare class LiveActivityHandle {
  readonly id: string
}

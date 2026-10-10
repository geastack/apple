/** @gea-host-no-property-writes */
export declare function requestLiveActivity(attributesJSON: string, contentStateJSON: string): LiveActivityHandle
/** @gea-host-no-property-writes */
export declare function updateLiveActivity(activity: LiveActivityHandle, contentStateJSON: string): void
/** @gea-host-no-property-writes */
export declare function endLiveActivity(activity: LiveActivityHandle): void

export declare class LiveActivityHandle {
  readonly id: string
}

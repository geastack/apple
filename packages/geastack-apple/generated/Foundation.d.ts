/** @gea-host-no-property-writes */
export declare function randomUUID(): string
/** @gea-host-no-property-writes */
export declare function localTimeZone(): string
/** @gea-host-no-property-writes */
export declare function sharedContainerPath(groupIdentifier: string): string
/** @gea-host-no-property-writes */
export declare function readTextFile(path: string): string
/** @gea-host-no-property-writes */
export declare function writeTextFile(path: string, text: string): void
/** @gea-host-no-property-writes */
export declare function watchPath(path: string, changed: () => void): number
/** @gea-host-no-property-writes */
export declare function stopWatchingPath(handle: number): void

export declare class NSObject {
}

export declare class NSData extends NSObject {
}

export declare class NSDictionary extends NSObject {
  static dictionary(): NSDictionary
}

export declare class NSURL extends NSObject {
  static URLWithString(URLString: string): NSURL | null
}

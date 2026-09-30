export declare function randomUUID(): string
export declare function localTimeZone(): string
export declare function sharedContainerPath(groupIdentifier: string): string
export declare function readTextFile(path: string): string
export declare function writeTextFile(path: string, text: string): void
export declare function watchPath(path: string, changed: () => void): number
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

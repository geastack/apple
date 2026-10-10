/** @gea-host-no-property-writes */
export declare function requestAuthorization(completed: (granted: boolean, error: string) => void): void
/** @gea-host-no-property-writes */
export declare function scheduleNotification(identifier: string, title: string, body: string, delaySeconds: number, completed: (error: string) => void): void
/** @gea-host-no-property-writes */
export declare function cancelNotification(identifier: string): void

/** @gea-host-no-property-writes */
export declare function authorizationStatus(): string
/** @gea-host-no-property-writes */
export declare function requestFullAccess(completed: (granted: boolean, error: string) => void): void
/** @gea-host-no-property-writes */
export declare function calendars(): string
/** @gea-host-no-property-writes */
export declare function events(startISO: string, endISO: string, calendarIdsJSON: string): string
/** @gea-host-no-property-writes */
export declare function watchChanges(changed: () => void): number
/** @gea-host-no-property-writes */
export declare function stopWatchingChanges(handle: number): void
/** @gea-host-no-property-writes */
export declare function saveEvent(eventJSON: string, span: string, completed: (id: string, error: string) => void): void
/** @gea-host-no-property-writes */
export declare function removeEvent(eventId: string, occurrenceDate: string, span: string, completed: (error: string) => void): void

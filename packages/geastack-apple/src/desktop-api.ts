import type { AppleFrameworkDefinition, AppleFunctionDefinition, AppleTypeReference } from './index.js'

const string: AppleTypeReference = { kind: 'primitive', name: 'string' }
const number: AppleTypeReference = { kind: 'primitive', name: 'number' }
const boolean: AppleTypeReference = { kind: 'primitive', name: 'boolean' }
const nothing: AppleTypeReference = { kind: 'primitive', name: 'void' }
const callback: AppleTypeReference = { kind: 'function', returns: nothing }
const completion: AppleTypeReference = {
  kind: 'function',
  returns: nothing,
  parameters: [{ name: 'error', type: string }]
}
const savedEventCompletion: AppleTypeReference = {
  kind: 'function',
  returns: nothing,
  parameters: [
    { name: 'id', type: string },
    { name: 'error', type: string }
  ]
}

// Each bridge body is a separate function, so the process-wide EKEventStore is
// kept as an associated object on the EKEventStore class.
const eventStore = `EKEventStore *store = nil;
@synchronized ([EKEventStore class]) {
  store = objc_getAssociatedObject([EKEventStore class], @selector(geaSharedEventStore));
  if (!store) {
    store = [[EKEventStore alloc] init];
    objc_setAssociatedObject([EKEventStore class], @selector(geaSharedEventStore), store, OBJC_ASSOCIATION_RETAIN);
  }
}`
// ISO 8601 with the local offset out; with or without fractional seconds in,
// so JavaScript's toISOString() round-trips.
const eventDates = `NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
iso.timeZone = [NSTimeZone localTimeZone];
NSISO8601DateFormatter *isoFraction = [[NSISO8601DateFormatter alloc] init];
isoFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
auto parseDate = [&](NSString *value) -> NSDate * {
  if (![value isKindOfClass:[NSString class]]) return nil;
  return [iso dateFromString:value] ?: [isoFraction dateFromString:value];
};`
const jsonText = `auto jsonText = [](id object) -> std::string {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
  return data ? std::string(static_cast<const char *>(data.bytes), data.length) : std::string("[]");
};`
const eventJSON = `auto availabilityName = [](EKEventAvailability availability) -> NSString * {
  switch (availability) {
    case EKEventAvailabilityBusy: return @"busy";
    case EKEventAvailabilityFree: return @"free";
    case EKEventAvailabilityTentative: return @"tentative";
    case EKEventAvailabilityUnavailable: return @"unavailable";
    default: return @"notSupported";
  }
};
auto statusName = [](EKEventStatus status) -> NSString * {
  switch (status) {
    case EKEventStatusConfirmed: return @"confirmed";
    case EKEventStatusTentative: return @"tentative";
    case EKEventStatusCanceled: return @"canceled";
    default: return @"none";
  }
};
auto eventObject = [&](EKEvent *event) -> NSDictionary * {
  return @{@"id": event.eventIdentifier ?: @"", @"externalId": event.calendarItemExternalIdentifier ?: @"",
    @"calendarId": event.calendar.calendarIdentifier ?: @"", @"title": event.title ?: @"",
    @"start": [iso stringFromDate:event.startDate], @"end": [iso stringFromDate:event.endDate],
    @"occurrenceDate": [iso stringFromDate:event.occurrenceDate ?: event.startDate],
    @"allDay": @(event.allDay), @"availability": availabilityName(event.availability),
    @"recurring": @(event.hasRecurrenceRules), @"status": statusName(event.status)};
};`
// An occurrence of a recurring event is addressed by its id plus the
// occurrenceDate events() reported; it is searched for a week either side.
const findEvent = `auto findEvent = [&](NSString *identifier, NSString *occurrence) -> EKEvent * {
  if (occurrence.length == 0) return [store eventWithIdentifier:identifier];
  NSDate *date = parseDate(occurrence);
  if (!date) return nil;
  NSPredicate *predicate = [store predicateForEventsWithStartDate:[date dateByAddingTimeInterval:-7 * 86400]
    endDate:[date dateByAddingTimeInterval:7 * 86400] calendars:nil];
  for (EKEvent *candidate in [store eventsMatchingPredicate:predicate])
    if ([candidate.eventIdentifier isEqualToString:identifier] && fabs([candidate.occurrenceDate timeIntervalSinceDate:date]) < 1) return candidate;
  return nil;
};
auto eventSpan = [](const std::string &value, EKSpan *span) -> bool {
  if (value == "thisEvent") { *span = EKSpanThisEvent; return true; }
  if (value == "futureEvents") { *span = EKSpanFutureEvents; return true; }
  return false;
};`

export const foundationServices: AppleFunctionDefinition[] = [
  {
    name: 'randomUUID',
    returns: string,
    bridgeBody: 'return gea::apple::Foundation::fromNSString([[NSUUID UUID] UUIDString]);'
  },
  {
    name: 'localTimeZone',
    returns: string,
    bridgeBody: 'return gea::apple::Foundation::fromNSString([[NSTimeZone localTimeZone] name]);'
  },
  {
    name: 'sharedContainerPath',
    returns: string,
    parameters: [{ name: 'groupIdentifier', type: string }],
    bridgeBody: `::NSURL *url = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:gea::apple::Foundation::toNSString(groupIdentifier)];
if (!url) throw std::runtime_error("App Group container is unavailable; check the application's entitlements");
return gea::apple::Foundation::fromNSString(url.path);`
  },
  {
    name: 'readTextFile',
    returns: string,
    parameters: [{ name: 'path', type: string }],
    bridgeBody: `NSError *error = nil;
NSString *text = [NSString stringWithContentsOfFile:gea::apple::Foundation::toNSString(path) encoding:NSUTF8StringEncoding error:&error];
if (!text) throw std::runtime_error(gea::apple::Foundation::fromNSString(error.localizedDescription));
return gea::apple::Foundation::fromNSString(text);`
  },
  {
    name: 'writeTextFile',
    returns: nothing,
    parameters: [
      { name: 'path', type: string },
      { name: 'text', type: string }
    ],
    bridgeBody: `NSError *error = nil;
if (![gea::apple::Foundation::toNSString(text) writeToFile:gea::apple::Foundation::toNSString(path) atomically:YES encoding:NSUTF8StringEncoding error:&error])
  throw std::runtime_error(gea::apple::Foundation::fromNSString(error.localizedDescription));`
  },
  {
    name: 'watchPath',
    returns: number,
    parameters: [
      { name: 'path', type: string },
      { name: 'changed', type: callback }
    ],
    bridgeBody: `const int descriptor = open(path.c_str(), O_EVTONLY);
if (descriptor < 0) throw std::runtime_error("Cannot open path for observation");
dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, descriptor,
  DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB,
  dispatch_get_main_queue());
if (!source) { close(descriptor); throw std::runtime_error("Cannot observe path"); }
dispatch_source_set_event_handler(source, ^{ if (changed) changed(); });
dispatch_source_set_cancel_handler(source, ^{ close(descriptor); });
const double handle = gea::apple::objc::retain((__bridge void *)source);
dispatch_resume(source);
return handle;`
  },
  {
    name: 'stopWatchingPath',
    returns: nothing,
    parameters: [{ name: 'handle', type: number }],
    bridgeBody: `dispatch_source_t source = (__bridge dispatch_source_t)gea::apple::objc::object(handle);
if (source) { dispatch_source_cancel(source); gea::apple::objc::release(handle); }`
  }
]

export const desktopFrameworks: AppleFrameworkDefinition[] = [
  {
    name: 'Security',
    bridgeHeaders: ['Security/Security.h', 'stdexcept'],
    functions: [
      {
        name: 'writePassword',
        returns: number,
        parameters: [
          { name: 'service', type: string },
          { name: 'account', type: string },
          { name: 'password', type: string }
        ],
        bridgeBody: `NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
  (__bridge id)kSecAttrService: gea::apple::Foundation::toNSString(service),
  (__bridge id)kSecAttrAccount: gea::apple::Foundation::toNSString(account)};
NSData *data = [NSData dataWithBytes:password.data() length:password.size()];
OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: data});
if (status == errSecItemNotFound) {
  NSMutableDictionary *item = [query mutableCopy];
  item[(__bridge id)kSecValueData] = data;
  status = SecItemAdd((__bridge CFDictionaryRef)item, nullptr);
}
return status;`
      },
      {
        name: 'readPassword',
        returns: string,
        parameters: [
          { name: 'service', type: string },
          { name: 'account', type: string }
        ],
        bridgeBody: `NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
  (__bridge id)kSecAttrService: gea::apple::Foundation::toNSString(service),
  (__bridge id)kSecAttrAccount: gea::apple::Foundation::toNSString(account),
  (__bridge id)kSecReturnData: @YES, (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
CFTypeRef result = nullptr;
const OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
if (status != errSecSuccess) throw std::runtime_error("Keychain read failed: " + std::to_string(status));
NSData *data = CFBridgingRelease(result);
return std::string(static_cast<const char *>(data.bytes), data.length);`
      },
      {
        name: 'deletePassword',
        returns: number,
        parameters: [
          { name: 'service', type: string },
          { name: 'account', type: string }
        ],
        bridgeBody: `return SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
  (__bridge id)kSecAttrService: gea::apple::Foundation::toNSString(service),
  (__bridge id)kSecAttrAccount: gea::apple::Foundation::toNSString(account)});`
      }
    ]
  },
  {
    name: 'UserNotifications',
    bridgeHeaders: ['UserNotifications/UserNotifications.h'],
    functions: [
      {
        name: 'requestAuthorization',
        returns: nothing,
        parameters: [
          {
            name: 'completed',
            type: {
              kind: 'function',
              returns: nothing,
              parameters: [
                { name: 'granted', type: boolean },
                { name: 'error', type: string }
              ]
            }
          }
        ],
        bridgeBody: `[[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
  completionHandler:^(BOOL granted, NSError *error) {
    const std::string message = gea::apple::Foundation::fromNSString(error.localizedDescription);
    dispatch_async(dispatch_get_main_queue(), ^{ if (completed) completed(granted, message); });
  }];`
      },
      {
        name: 'scheduleNotification',
        returns: nothing,
        parameters: [
          { name: 'identifier', type: string },
          { name: 'title', type: string },
          { name: 'body', type: string },
          { name: 'delaySeconds', type: number },
          { name: 'completed', type: completion }
        ],
        bridgeBody: `if (!std::isfinite(delaySeconds) || delaySeconds <= 0) { if (completed) completed("delaySeconds must be positive and finite"); return; }
UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
content.title = gea::apple::Foundation::toNSString(title);
content.body = gea::apple::Foundation::toNSString(body);
UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delaySeconds repeats:NO];
UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:gea::apple::Foundation::toNSString(identifier) content:content trigger:trigger];
[[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
  const std::string message = gea::apple::Foundation::fromNSString(error.localizedDescription);
  dispatch_async(dispatch_get_main_queue(), ^{ if (completed) completed(message); });
}];`
      },
      {
        name: 'cancelNotification',
        returns: nothing,
        parameters: [{ name: 'identifier', type: string }],
        bridgeBody:
          '[[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[gea::apple::Foundation::toNSString(identifier)]];'
      }
    ]
  },
  {
    name: 'EventKit',
    bridgeHeaders: ['EventKit/EventKit.h', 'objc/runtime.h', 'cmath', 'stdexcept'],
    functions: [
      {
        name: 'authorizationStatus',
        returns: string,
        // Raw values: 3 is fullAccess on macOS 14+ and the older "authorized".
        bridgeBody: `switch (static_cast<NSInteger>([EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent])) {
  case 1: return "restricted";
  case 2: return "denied";
  case 3: return "fullAccess";
  case 4: return "writeOnly";
  default: return "notDetermined";
}`
      },
      {
        name: 'requestFullAccess',
        returns: nothing,
        parameters: [
          {
            name: 'completed',
            type: {
              kind: 'function',
              returns: nothing,
              parameters: [
                { name: 'granted', type: boolean },
                { name: 'error', type: string }
              ]
            }
          }
        ],
        bridgeBody: `${eventStore}
void (^finish)(BOOL, NSError *) = ^(BOOL granted, NSError *error) {
  const std::string message = gea::apple::Foundation::fromNSString(error.localizedDescription);
  dispatch_async(dispatch_get_main_queue(), ^{ if (completed) completed(granted, message); });
};
if (@available(macOS 14.0, iOS 17.0, *)) {
  [store requestFullAccessToEventsWithCompletion:finish];
} else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [store requestAccessToEntityType:EKEntityTypeEvent completion:finish];
#pragma clang diagnostic pop
}`
      },
      {
        name: 'calendars',
        returns: string,
        bridgeBody: `${eventStore}
${jsonText}
auto sourceTypeName = [](EKSourceType type) -> NSString * {
  switch (type) {
    case EKSourceTypeLocal: return @"local";
    case EKSourceTypeExchange: return @"exchange";
    case EKSourceTypeCalDAV: return @"calDAV";
    case EKSourceTypeMobileMe: return @"mobileMe";
    case EKSourceTypeSubscribed: return @"subscribed";
    case EKSourceTypeBirthdays: return @"birthdays";
    default: return @"unknown";
  }
};
CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
NSMutableArray *result = [NSMutableArray array];
NSArray<EKCalendar *> *calendars = [[store calendarsForEntityType:EKEntityTypeEvent] sortedArrayUsingDescriptors:@[
  [NSSortDescriptor sortDescriptorWithKey:@"source.title" ascending:YES],
  [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]]];
for (EKCalendar *calendar in calendars) {
  NSString *color = @"";
  CGColorRef matched = calendar.CGColor ? CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, calendar.CGColor, nullptr) : nullptr;
  if (matched && CGColorGetNumberOfComponents(matched) >= 3) {
    const CGFloat *rgb = CGColorGetComponents(matched);
    auto channel = [](CGFloat value) { return static_cast<int>(std::lround(std::fmin(std::fmax(value, 0.0), 1.0) * 255)); };
    color = [NSString stringWithFormat:@"#%02X%02X%02X", channel(rgb[0]), channel(rgb[1]), channel(rgb[2])];
  }
  if (matched) CGColorRelease(matched);
  [result addObject:@{@"id": calendar.calendarIdentifier ?: @"", @"title": calendar.title ?: @"", @"color": color,
    @"source": calendar.source.title ?: @"", @"sourceType": sourceTypeName(calendar.source.sourceType),
    @"allowsModifications": @(calendar.allowsContentModifications)}];
}
if (srgb) CGColorSpaceRelease(srgb);
return jsonText(result);`
      },
      {
        name: 'events',
        returns: string,
        parameters: [
          { name: 'startISO', type: string },
          { name: 'endISO', type: string },
          { name: 'calendarIdsJSON', type: string }
        ],
        bridgeBody: `${eventStore}
${eventDates}
${jsonText}
${eventJSON}
NSDate *start = parseDate(gea::apple::Foundation::toNSString(startISO));
NSDate *end = parseDate(gea::apple::Foundation::toNSString(endISO));
if (!start || !end) throw std::runtime_error("events: start and end must be ISO 8601 date-times");
NSMutableArray<EKCalendar *> *calendars = nil;
if (!calendarIdsJSON.empty()) {
  NSData *data = [gea::apple::Foundation::toNSString(calendarIdsJSON) dataUsingEncoding:NSUTF8StringEncoding];
  id ids = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![ids isKindOfClass:[NSArray class]]) throw std::runtime_error("events: calendarIdsJSON must be a JSON array of calendar ids");
  if ([ids count] > 0) {
    calendars = [NSMutableArray array];
    for (id identifier in ids) {
      EKCalendar *calendar = [identifier isKindOfClass:[NSString class]] ? [store calendarWithIdentifier:identifier] : nil;
      if (calendar) [calendars addObject:calendar];
    }
    if (calendars.count == 0) return "[]";
  }
}
NSPredicate *predicate = [store predicateForEventsWithStartDate:start endDate:end calendars:calendars];
NSArray<EKEvent *> *events = [[store eventsMatchingPredicate:predicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
NSMutableArray *result = [NSMutableArray arrayWithCapacity:events.count];
for (EKEvent *event in events) [result addObject:eventObject(event)];
return jsonText(result);`
      },
      {
        name: 'watchChanges',
        returns: number,
        parameters: [{ name: 'changed', type: callback }],
        bridgeBody: `${eventStore}
id observer = [[NSNotificationCenter defaultCenter] addObserverForName:EKEventStoreChangedNotification object:store
  queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *) { if (changed) changed(); }];
return gea::apple::objc::retain((__bridge void *)observer);`
      },
      {
        name: 'stopWatchingChanges',
        returns: nothing,
        parameters: [{ name: 'handle', type: number }],
        bridgeBody: `id observer = (__bridge id)gea::apple::objc::object(handle);
if (observer) { [[NSNotificationCenter defaultCenter] removeObserver:observer]; gea::apple::objc::release(handle); }`
      },
      {
        name: 'saveEvent',
        returns: nothing,
        parameters: [
          { name: 'eventJSON', type: string },
          { name: 'span', type: string },
          { name: 'completed', type: savedEventCompletion }
        ],
        bridgeBody: `${eventStore}
${eventDates}
${findEvent}
// The block copies what it names; a reference the lambda captured would
// dangle once this function returns, so copy the callback into the lambda.
auto finish = [&](NSString *identifier, std::string error) {
  auto callback = completed;
  const std::string saved = gea::apple::Foundation::fromNSString(identifier);
  dispatch_async(dispatch_get_main_queue(), ^{ if (callback) callback(saved, error); });
};
EKSpan eventKitSpan;
if (!eventSpan(span, &eventKitSpan)) return finish(nil, "span must be thisEvent or futureEvents");
NSData *data = [gea::apple::Foundation::toNSString(eventJSON) dataUsingEncoding:NSUTF8StringEncoding];
NSDictionary *fields = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
if (![fields isKindOfClass:[NSDictionary class]]) return finish(nil, "eventJSON must be a JSON object");
auto text = [&](NSString *key) -> NSString * { id value = fields[key]; return [value isKindOfClass:[NSString class]] ? value : nil; };
EKEvent *event = nil;
if (text(@"id").length) {
  event = findEvent(text(@"id"), text(@"occurrenceDate"));
  if (!event) return finish(nil, "No event with that id and occurrenceDate");
  if (!event.calendar.allowsContentModifications) return finish(nil, "The event's calendar does not allow modifications");
} else {
  event = [EKEvent eventWithEventStore:store];
  if (!text(@"calendarId") || !fields[@"start"] || !fields[@"end"]) return finish(nil, "A new event needs calendarId, start and end");
}
if (text(@"calendarId")) {
  EKCalendar *calendar = [store calendarWithIdentifier:text(@"calendarId")];
  if (!calendar) return finish(nil, "No calendar with that calendarId");
  if (!calendar.allowsContentModifications) return finish(nil, "The calendar does not allow modifications");
  event.calendar = calendar;
}
if (fields[@"start"]) { NSDate *date = parseDate(fields[@"start"]); if (!date) return finish(nil, "start must be an ISO 8601 date-time"); event.startDate = date; }
if (fields[@"end"]) { NSDate *date = parseDate(fields[@"end"]); if (!date) return finish(nil, "end must be an ISO 8601 date-time"); event.endDate = date; }
if ([event.endDate compare:event.startDate] == NSOrderedAscending) return finish(nil, "end must not be before start");
if (fields[@"title"]) event.title = text(@"title") ?: @"";
if (fields[@"location"]) event.location = text(@"location");
if (fields[@"notes"]) event.notes = text(@"notes");
if ([fields[@"allDay"] isKindOfClass:[NSNumber class]]) event.allDay = [fields[@"allDay"] boolValue];
if (text(@"availability")) {
  NSDictionary *availability = @{@"busy": @(EKEventAvailabilityBusy), @"free": @(EKEventAvailabilityFree),
    @"tentative": @(EKEventAvailabilityTentative), @"unavailable": @(EKEventAvailabilityUnavailable)};
  NSNumber *value = availability[text(@"availability")];
  if (!value) return finish(nil, "availability must be busy, free, tentative or unavailable");
  event.availability = static_cast<EKEventAvailability>(value.integerValue);
}
NSError *error = nil;
if (![store saveEvent:event span:eventKitSpan commit:YES error:&error]) return finish(nil, gea::apple::Foundation::fromNSString(error.localizedDescription));
finish(event.eventIdentifier, "");`
      },
      {
        name: 'removeEvent',
        returns: nothing,
        parameters: [
          { name: 'eventId', type: string },
          { name: 'occurrenceDate', type: string },
          { name: 'span', type: string },
          { name: 'completed', type: completion }
        ],
        bridgeBody: `${eventStore}
${eventDates}
${findEvent}
auto finish = [&](std::string error) {
  auto callback = completed;
  dispatch_async(dispatch_get_main_queue(), ^{ if (callback) callback(error); });
};
EKSpan eventKitSpan;
if (!eventSpan(span, &eventKitSpan)) return finish("span must be thisEvent or futureEvents");
EKEvent *event = findEvent(gea::apple::Foundation::toNSString(eventId), gea::apple::Foundation::toNSString(occurrenceDate));
if (!event) return finish("No event with that id and occurrenceDate");
if (!event.calendar.allowsContentModifications) return finish("The event's calendar does not allow modifications");
NSError *error = nil;
if (![store removeEvent:event span:eventKitSpan commit:YES error:&error]) return finish(gea::apple::Foundation::fromNSString(error.localizedDescription));
finish("");`
      }
    ]
  }
]

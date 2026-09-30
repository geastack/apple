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
  }
]

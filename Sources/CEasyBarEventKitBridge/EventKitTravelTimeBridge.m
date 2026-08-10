#import "CEasyBarEventKitBridge.h"

static NSString *const EasyBarTravelTimeKey = @"travelTime";

bool easybar_eventkit_read_travel_time(NSObject *object, double *seconds) {
  if (object == nil || seconds == NULL) {
    return false;
  }

  SEL getter = NSSelectorFromString(EasyBarTravelTimeKey);
  if (![object respondsToSelector:getter]) {
    return false;
  }

  @try {
    id value = [object valueForKey:EasyBarTravelTimeKey];
    if (![value isKindOfClass:[NSNumber class]]) {
      return false;
    }
    *seconds = [(NSNumber *)value doubleValue];
    return true;
  } @catch (__unused NSException *exception) {
    return false;
  }
}

bool easybar_eventkit_write_travel_time(NSObject *object, double seconds) {
  if (object == nil) {
    return false;
  }

  SEL setter = NSSelectorFromString(@"setTravelTime:");
  if (![object respondsToSelector:setter]) {
    return false;
  }

  @try {
    [object setValue:@(seconds) forKey:EasyBarTravelTimeKey];
    return true;
  } @catch (__unused NSException *exception) {
    return false;
  }
}

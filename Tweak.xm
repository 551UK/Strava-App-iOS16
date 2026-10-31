#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <substrate.h>
#import <dlfcn.h>

// App-specific version compatibility experiment; credentials are not touched.
static NSString *appV = @"486.0.2", *iosV = @"17.7.2", *buildV = nil;
static BOOL active = YES, osSpoof = YES, headerSpoof = YES;
static BOOL mainStrava(NSBundle *b) {
  return b == [NSBundle mainBundle] &&
    [[b bundleIdentifier] isEqualToString:@"com.strava.stravaride"];
}
static NSString *change(NSString *v, NSString *field) {
  if (!active || !headerSpoof || ![v isKindOfClass:[NSString class]] ||
      ![field isKindOfClass:[NSString class]]) return v;
  NSString *name = [field lowercaseString];
  if (!([name isEqualToString:@"user-agent"] || [name containsString:@"version"] ||
        [name containsString:@"strava-client"] || [name isEqualToString:@"x-app-build"]))
    return v;
  NSString *s = [v stringByReplacingOccurrencesOfString:@"422.0.1" withString:appV];
  return [s stringByReplacingOccurrencesOfString:@"375.0.0" withString:appV];
}
static NSDictionary *changeDict(NSDictionary *d) {
  if (!active || !headerSpoof || ![d isKindOfClass:[NSDictionary class]]) return d;
  NSMutableDictionary *m = [d mutableCopy];
  for (id k in d)
    if ([k isKindOfClass:[NSString class]] && [d[k] isKindOfClass:[NSString class]])
      m[k] = change(d[k], k);
  return m;
}
%group Version
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)k {
  if (active && mainStrava(self)) {
    if ([k isEqualToString:@"CFBundleShortVersionString"]) return appV;
    if (buildV.length && [k isEqualToString:@"CFBundleVersion"]) return buildV;
  }
  return %orig;
}
- (NSDictionary *)infoDictionary {
  NSDictionary *d = %orig;
  if (!active || !mainStrava(self) || !d) return d;
  NSMutableDictionary *m = [d mutableCopy];
  m[@"CFBundleShortVersionString"] = appV;
  if (buildV.length) m[@"CFBundleVersion"] = buildV;
  return m;
}
%end
%end
%group OS
%hook UIDevice
- (NSString *)systemVersion {
  if (active && osSpoof) return iosV;
  return %orig;
}
%end
%end
%group Headers
%hook NSMutableURLRequest
- (void)setValue:(NSString *)v forHTTPHeaderField:(NSString *)k { %orig(change(v,k),k); }
- (void)addValue:(NSString *)v forHTTPHeaderField:(NSString *)k { %orig(change(v,k),k); }
- (void)setAllHTTPHeaderFields:(NSDictionary *)d { %orig(changeDict(d)); }
%end
%hook NSURLSessionConfiguration
- (void)setHTTPAdditionalHeaders:(NSDictionary *)d { %orig(changeDict(d)); }
%end
%end
typedef const void *(*CFGet)(CFBundleRef,CFStringRef);
static CFGet origCF = NULL;
static const void *replacementCF(CFBundleRef b, CFStringRef k) {
  if (active && b == CFBundleGetMainBundle() && k) {
    if (CFEqual(k,CFSTR("CFBundleShortVersionString"))) return (__bridge const void *)appV;
    if (buildV.length && CFEqual(k,CFSTR("CFBundleVersion")))
      return (__bridge const void *)buildV;
  }
  return origCF ? origCF(b,k) : NULL;
}
%ctor {
  @autoreleasepool {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.strava.stravaride"]) return;
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:
      @"/var/jb/Library/Preferences/com.551uk.stravacompat.plist"];
    if ([p[@"Enabled"] respondsToSelector:@selector(boolValue)]) active = [p[@"Enabled"] boolValue];
    if ([p[@"SpoofIOSVersion"] respondsToSelector:@selector(boolValue)]) osSpoof = [p[@"SpoofIOSVersion"] boolValue];
    if ([p[@"SpoofHeaderVersions"] respondsToSelector:@selector(boolValue)]) headerSpoof = [p[@"SpoofHeaderVersions"] boolValue];
    if ([p[@"AppVersion"] isKindOfClass:[NSString class]] && [p[@"AppVersion"] length]) appV = [p[@"AppVersion"] copy];
    if ([p[@"IOSVersion"] isKindOfClass:[NSString class]] && [p[@"IOSVersion"] length]) iosV = [p[@"IOSVersion"] copy];
    if ([p[@"BuildNumber"] isKindOfClass:[NSString class]] && [p[@"BuildNumber"] length]) buildV = [p[@"BuildNumber"] copy];
    if (!active) return;
    %init(Version);
    if (osSpoof) %init(OS);
    if (headerSpoof) %init(Headers);
    void *s = dlsym(RTLD_DEFAULT,"CFBundleGetValueForInfoDictionaryKey");
    if (s) MSHookFunction(s,(void *)replacementCF,(void **)&origCF);
    NSLog(@"[StravaCompat] Version %@, iOS %@", appV, iosV);
  }
}

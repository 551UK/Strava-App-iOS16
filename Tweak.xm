#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>
#import <stdlib.h>

// Strava 422.0.1 compatibility diagnostic build.
// No global iOS spoof, CoreFoundation inline hook, token manipulation,
// server-response modification or subscription bypass.
static NSBundle *sMainBundle = nil;
static NSString *sVersion = @"486.0.2";
static NSString *sIOSVersion = @"17.7.2";
static BOOL sEnabled = YES;
static BOOL sLocalCheck = YES;
static BOOL sHeaderSpoof = YES;
static BOOL sIOSSpoof = NO;

static NSString *RewrittenHeader(NSString *value, NSString *field) {
    if (!sEnabled || !sHeaderSpoof ||
        ![value isKindOfClass:[NSString class]] ||
        ![field isKindOfClass:[NSString class]]) return value;
    NSString *key = [field lowercaseString];
    if (!([key isEqualToString:@"user-agent"] ||
          [key containsString:@"version"] ||
          [key containsString:@"strava-client"] ||
          [key isEqualToString:@"x-app-build"])) return value;
    NSString *updated = [value stringByReplacingOccurrencesOfString:@"422.0.1"
                                                           withString:sVersion];
    return [updated stringByReplacingOccurrencesOfString:@"375.0.0"
                                              withString:sVersion];
}
static NSDictionary *RewrittenHeaders(NSDictionary *headers) {
    if (!sEnabled || !sHeaderSpoof ||
        ![headers isKindOfClass:[NSDictionary class]]) return headers;
    NSMutableDictionary *copy = [headers mutableCopy];
    for (id field in headers) {
        id value = [headers objectForKey:field];
        if ([field isKindOfClass:[NSString class]] &&
            [value isKindOfClass:[NSString class]]) {
            [copy setObject:RewrittenHeader(value, field) forKey:field];
        }
    }
    return copy;
}

%group AppBundle
%hook NSBundle
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (sEnabled && self == sMainBundle && [key isKindOfClass:[NSString class]]
        && [key isEqualToString:@"CFBundleShortVersionString"]) return sVersion;
    return %orig;
}
%end
%end

%group HttpHeaders
%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(RewrittenHeader(value, field), field);
}
- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig(RewrittenHeader(value, field), field);
}
- (void)setAllHTTPHeaderFields:(NSDictionary *)headers {
    %orig(RewrittenHeaders(headers));
}
%end
%hook NSURLSessionConfiguration
- (void)setHTTPAdditionalHeaders:(NSDictionary *)headers {
    %orig(RewrittenHeaders(headers));
}
%end
%end

%group OptionalIOS
%hook UIDevice
- (NSString *)systemVersion {
    if (sEnabled && sIOSSpoof) return sIOSVersion;
    return %orig;
}
%end
%end

// Confirmed in the 422.0.1 executable: Swift ObjC proxy
// Strava.ClientConfigManagerObjcProxy with selector isAppVersionValid.
// Dynamically validate a zero-argument Boolean method before hooking.
// Never add a hook when the class/selector/signature is absent.
static BOOL (*sOriginalIsAppVersionValid)(id, SEL) = NULL;
static BOOL AlwaysValidVersion(id receiver, SEL selector) {
    if (sEnabled && sLocalCheck) return YES;
    return sOriginalIsAppVersionValid ?
           sOriginalIsAppVersionValid(receiver, selector) : YES;
}
static void InstallLocalCheckHook(void) {
    if (!sLocalCheck) return;
    Class cls = objc_lookUpClass("_TtC6Strava28ClientConfigManagerObjcProxy");
    if (!cls) cls = objc_lookUpClass("Strava.ClientConfigManagerObjcProxy");
    if (!cls) {
        NSLog(@"[StravaCompat] Local check class not found; skipping");
        return;
    }
    SEL sel = sel_registerName("isAppVersionValid");
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 2) {
        NSLog(@"[StravaCompat] Local check selector/signature missing; skipping");
        return;
    }
    char *resultType = method_copyReturnType(method);
    BOOL compatible = resultType && (strcmp(resultType, "B") == 0 ||
                                      strcmp(resultType, "c") == 0 ||
                                      strcmp(resultType, "C") == 0);
    if (resultType) free(resultType);
    if (!compatible) {
        NSLog(@"[StravaCompat] Local check return type not Boolean; skipping");
        return;
    }
    MSHookMessageEx(cls, sel, (IMP)AlwaysValidVersion,
                    (IMP *)&sOriginalIsAppVersionValid);
    NSLog(@"[StravaCompat] Installed guarded isAppVersionValid hook");
}

%ctor {
    @autoreleasepool {
        // The injection filter already scopes this tweak to Strava.
        sMainBundle = [NSBundle mainBundle];
        if (![[sMainBundle bundleIdentifier] isEqualToString:@"com.strava.stravaride"])
            return;

        NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:
            @"/var/jb/Library/Preferences/com.551uk.stravacompat.plist"];
        if ([p[@"Enabled"] respondsToSelector:@selector(boolValue)])
            sEnabled = [p[@"Enabled"] boolValue];
        if ([p[@"EnableLocalVersionCheck"] respondsToSelector:@selector(boolValue)])
            sLocalCheck = [p[@"EnableLocalVersionCheck"] boolValue];
        if ([p[@"SpoofHeaderVersions"] respondsToSelector:@selector(boolValue)])
            sHeaderSpoof = [p[@"SpoofHeaderVersions"] boolValue];
        if ([p[@"SpoofIOSVersion"] respondsToSelector:@selector(boolValue)])
            sIOSSpoof = [p[@"SpoofIOSVersion"] boolValue];
        if ([p[@"AppVersion"] isKindOfClass:[NSString class]] && [p[@"AppVersion"] length])
            sVersion = [p[@"AppVersion"] copy];
        if ([p[@"IOSVersion"] isKindOfClass:[NSString class]] && [p[@"IOSVersion"] length])
            sIOSVersion = [p[@"IOSVersion"] copy];
        if (!sEnabled) {
            NSLog(@"[StravaCompat] Disabled by preferences");
            return;
        }

        %init(AppBundle);
        if (sHeaderSpoof) %init(HttpHeaders);
        if (sIOSSpoof) %init(OptionalIOS);
        InstallLocalCheckHook();
        NSLog(@"[StravaCompat] v0.1.1 ready; version=%@ local=%d headers=%d iOS=%d",
              sVersion, sLocalCheck, sHeaderSpoof, sIOSSpoof);
    }
}

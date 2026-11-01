#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
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


// Preferences are written by PreferenceLoader in the mobile user domain.
// A sandbox extension allows this App Store process to read the values.
static NSString *const sPreferenceDomain = @"com.551uk.stravacompat";
static void *sSandyHandle = NULL;
typedef int (*SandyApplyFn)(const char *);
static void EnablePreferenceReadAccess(void) {
    const char *candidates[] = {
        "/var/jb/usr/lib/libsandy.dylib",
        "/usr/lib/libsandy.dylib",
        "libsandy.dylib", NULL
    };
    for (int i = 0; candidates[i] && !sSandyHandle; i++)
        sSandyHandle = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (!sSandyHandle) {
        NSLog(@"[StravaCompat] libSandy unavailable; trying CFPreferences fallback");
        return;
    }
    SandyApplyFn applyProfile = (SandyApplyFn)dlsym(sSandyHandle,"libSandy_applyProfile");
    if (applyProfile && applyProfile("StravaCompat_Preferences") == 0)
        NSLog(@"[StravaCompat] Settings sandbox access enabled");
    else
        NSLog(@"[StravaCompat] Could not apply settings sandbox profile");
}
static NSDictionary *GetPreferences(void) {
    EnablePreferenceReadAccess();
    NSArray *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.551uk.stravacompat.plist",
        @"/var/mobile/Library/Preferences/com.551uk.stravacompat.plist",
        @"/var/jb/Library/Preferences/com.551uk.stravacompat.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([prefs isKindOfClass:[NSDictionary class]]) return prefs;
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)sPreferenceDomain);
    CFArrayRef keys = CFPreferencesCopyKeyList(
        (__bridge CFStringRef)sPreferenceDomain,
        kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    if (!keys) return nil;
    CFDictionaryRef dict = CFPreferencesCopyMultiple(
        keys, (__bridge CFStringRef)sPreferenceDomain,
        kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    CFRelease(keys);
    return dict ? CFBridgingRelease(dict) : nil;
}
static NSString *ValidateVersion(id candidate) {
    if (![candidate isKindOfClass:[NSString class]]) return nil;
    NSString *value = [(NSString *)candidate
        stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length < 3 || value.length > 32) return nil;
    NSArray *parts = [value componentsSeparatedByString:@"."];
    if (parts.count < 2 || parts.count > 6) return nil;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *part in parts) {
        if (part.length == 0 || part.length > 10 ||
            [part rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound)
            return nil;
    }
    return value;
}

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

        NSDictionary *p = GetPreferences();
        if ([p[@"Enabled"] respondsToSelector:@selector(boolValue)])
            sEnabled = [p[@"Enabled"] boolValue];
        if ([p[@"EnableLocalVersionCheck"] respondsToSelector:@selector(boolValue)])
            sLocalCheck = [p[@"EnableLocalVersionCheck"] boolValue];
        if ([p[@"SpoofHeaderVersions"] respondsToSelector:@selector(boolValue)])
            sHeaderSpoof = [p[@"SpoofHeaderVersions"] boolValue];
        if ([p[@"SpoofIOSVersion"] respondsToSelector:@selector(boolValue)])
            sIOSSpoof = [p[@"SpoofIOSVersion"] boolValue];
        NSString *appVersion = ValidateVersion(p[@"AppVersion"]);
        if (appVersion) sVersion = [appVersion copy];
        NSString *osVersion = ValidateVersion(p[@"IOSVersion"]);
        if (osVersion) sIOSVersion = [osVersion copy];
        if (!sEnabled) {
            NSLog(@"[StravaCompat] Disabled by preferences");
            return;
        }

        %init(AppBundle);
        if (sHeaderSpoof) %init(HttpHeaders);
        if (sIOSSpoof) %init(OptionalIOS);
        InstallLocalCheckHook();
        NSLog(@"[StravaCompat] ready; version=%@ local=%d headers=%d iOS=%d",
              sVersion, sLocalCheck, sHeaderSpoof, sIOSSpoof);
    }
}

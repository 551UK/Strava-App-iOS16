#import "StravaCompatRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

static NSString *const kDomain = @"com.551uk.stravacompat";
static NSString *const kNotify = @"com.551uk.stravacompat/preferences.changed";

static id ReadValue(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    return value ? CFBridgingRelease(value) : nil;
}
static void SaveValue(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kNotify, NULL, NULL, true);
}
static BOOL IsValidVersion(NSString *value) {
    if (![value isKindOfClass:[NSString class]] ||
        value.length < 3 || value.length > 32) return NO;
    NSArray *parts = [value componentsSeparatedByString:@"."];
    if (parts.count < 2 || parts.count > 6) return NO;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *part in parts) {
        if (!part.length || part.length > 10 ||
            [part rangeOfCharacterFromSet:[digits invertedSet]].location != NSNotFound)
            return NO;
    }
    return YES;
}

@implementation StravaCompatRootListController
- (NSArray *)specifiers {
    if (!_specifiers)
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    return ReadValue(key) ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    if ([key isEqualToString:@"AppVersion"] || [key isEqualToString:@"IOSVersion"]) {
        NSString *clean = [value isKindOfClass:[NSString class]]
          ? [value stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        if (!IsValidVersion(clean)) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"Invalid Version"
                message:@"Enter numbers separated by dots, for example 486.0.2 or 17.7.2."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self reloadSpecifiers];
            return;
        }
        value = clean;
    }
    SaveValue(key, value);
}
- (void)resetDefaults {
    [self.view endEditing:YES];
    NSDictionary *defaults = @{
        @"Enabled": @YES,
        @"AppVersion": @"486.0.2",
        @"EnableLocalVersionCheck": @YES,
        @"SpoofHeaderVersions": @YES,
        @"SpoofIOSVersion": @NO,
        @"IOSVersion": @"17.7.2"
    };
    for (NSString *key in defaults)
        SaveValue(key, defaults[key]);
    [self reloadSpecifiers];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Default Settings Restored"
        message:@"Fully close and reopen Strava to apply these changes."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/Strava-App-iOS16"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
@end

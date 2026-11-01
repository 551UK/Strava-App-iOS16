#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface StravaCompatRootListController : PSListController
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)resetDefaults;
- (void)openGitHub;
@end

TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := StravaCompatPrefs
StravaCompatPrefs_FILES := StravaCompatRootListController.m
StravaCompatPrefs_FRAMEWORKS := Foundation UIKit CoreFoundation
StravaCompatPrefs_PRIVATE_FRAMEWORKS := Preferences
StravaCompatPrefs_INSTALL_PATH := /Library/PreferenceBundles
StravaCompatPrefs_CFLAGS := -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk

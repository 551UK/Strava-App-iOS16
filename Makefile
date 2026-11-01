TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := StravaCompat
StravaCompat_FILES := Tweak.xm
StravaCompat_CFLAGS := -fobjc-arc
StravaCompat_FRAMEWORKS := Foundation UIKit CoreFoundation
StravaCompat_LIBRARIES := substrate
include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

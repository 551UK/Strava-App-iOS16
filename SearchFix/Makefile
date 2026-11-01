TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME := StravaSearch16
StravaSearch16_FILES := Diagnostics.xm Bridge.m SharedRoutes.mm
StravaSearch16_CFLAGS := -fobjc-arc -fblocks
StravaSearch16_FRAMEWORKS := Foundation UIKit MapKit CoreLocation WebKit SafariServices
StravaSearch16_LIBRARIES := substrate
include $(THEOS_MAKE_PATH)/tweak.mk

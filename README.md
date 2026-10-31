# StravaCompat iOS16

Experimental rootless tweak for Strava 422.0.1 on jailbroken iOS 16 with Dopamine and ElleKit.

It reports Strava 486.0.2 and iOS 17.7.2 within the Strava app, and updates version text in existing selected HTTP headers. Build numbers are not spoofed unless configured. No passwords, tokens, response bodies, signatures, or subscription data are touched.

**Login is not yet verified.** A server-side minimum version requirement may involve more than version reporting.

## Install

Download the rootless .deb from the repository [Releases](https://github.com/551UK/Strava-App-iOS16/releases). Install through Sileo or Zebra. Ensure Choicy permits tweak injection into Strava, then force-quit and reopen Strava.

## Settings

For custom settings copy the sample file com.551uk.stravacompat.plist to /var/jb/Library/Preferences/com.551uk.stravacompat.plist in Filza. Supported keys: Enabled, AppVersion, BuildNumber, SpoofIOSVersion, IOSVersion, SpoofHeaderVersions. Close and restart the app after changing. Disable SpoofIOSVersion first if the app crashes.

## Build

GitHub Actions compiles a rootless Theos package on push to main and attaches the package to a GitHub Release. Local builds: make clean package FINALPACKAGE=1 with Theos and the iOS SDK installed. No Strava IPA is included.

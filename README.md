# StravaCompat for iOS 16

StravaCompat is a rootless jailbreak tweak designed to help **Strava 422.0.1** run on **iOS 16** by addressing local app-version checks.

## Features

- Reports **Strava 486.0.2** when the app requests its main bundle's short version string.
- Handles the local `isAppVersionValid` check, when its method and Boolean signature match the expected form.
- Replaces older Strava versions in selected outgoing HTTP headers.
- Supports optional iOS-version spoofing, **disabled by default** for startup compatibility.
- Limits tweak injection to Strava (`com.strava.stravaride`).

These changes do not alter passwords, authentication tokens, paid subscriptions, or server responses. Strava's server-side requirements may still apply.

## Compatibility

**Strava app:** 422.0.1
**iOS:** 16.0 or newer, with a compatible rootless jailbreak
**Environment:** Dopamine / ElleKit
**Package ID:** `com.551uk.stravacompat`

## Configuration

Optional settings file: `/var/jb/Library/Preferences/com.551uk.stravacompat.plist`

Settings: `Enabled`, `AppVersion`, `EnableLocalVersionCheck`, `SpoofHeaderVersions`, `SpoofIOSVersion`, `IOSVersion`. Fully close and restart Strava after changing any setting.

## Build

Build from source using Theos and an iOS SDK:

```sh
make clean package FINALPACKAGE=1
```

No Strava IPA is included in this repository.

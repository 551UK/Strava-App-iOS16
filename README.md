# StravaCompat for iOS 16

StravaCompat is a rootless jailbreak tweak that helps **Strava 422.0.1** on **iOS 16** by addressing its local app-version checks.

## Features

- Editable **Strava Version** field in iOS Settings (default **486.0.2**).
- Spoofs the app's main-bundle short version and updates selected version-related HTTP headers.
- Handles the local `isAppVersionValid` check when the class, selector and signature match.
- Optional **iOS Version** field (default **17.7.2**) and separate enable switch, off by default for stability.
- Enable/disable switch and **Restore Defaults** button.
- Genuine Strava app icon in the iOS Settings tweak list.
- Injection limited to Strava (`com.strava.stravaride`).

The spoofed version does not install newer Strava functionality or guarantee server-side acceptance. Passwords, authentication tokens, subscriptions and server responses are not modified.

## Compatibility

- **Strava:** 422.0.1
- **iOS:** iOS 16 with rootless Dopamine / ElleKit
- **Dependencies:** PreferenceLoader, libSandy and MobileSubstrate-compatible injection

## Settings

Open **iOS Settings → StravaCompat**, enter a version, then fully close and reopen Strava to apply it. Keep iOS spoofing off unless needed. **Restore Defaults** returns to the default version and switches.

## Build

With Theos and a compatible iOS SDK on macOS:

```sh
python3 scripts/prepare-icon.py
make clean package FINALPACKAGE=1
```

This repository does not include a Strava IPA.

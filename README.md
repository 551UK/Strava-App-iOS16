# StravaCompat iOS16

Experimental compatibility tweak for **Strava 422.0.1 on rootless iOS 16 / Dopamine / ElleKit**.

## Changes in 0.1.1

Version 0.1.0 caused an instant crash for the first tester. The precise crash reason is not confirmed without a crash report, but broad startup hooks were a risk. This release removes the CoreFoundation function hook and the NSBundle infoDictionary hook, and **disables iOS version spoofing by default**.

The Strava 422.0.1 executable contains the ObjC-visible Swift class **Strava.ClientConfigManagerObjcProxy** and an **isAppVersionValid** selector. Version 0.1.1 attempts to hook this local validation method, **only if the class, selector and zero-argument Boolean signature are present at runtime**. Otherwise it logs that the hook was skipped. It also reports Strava **486.0.2** from NSBundle objectForInfoDictionaryKey and replaces old version strings in selected request headers.

The same executable includes ClientStartUpConfiguration with a GraphQL query for clientConfiguration.forceUpdate. This is a *server-returned* requirement, and local validation spoofing cannot guarantee that the server will accept a 422 authentication client. This build does not falsify authentication results, signatures or responses.

**Test status:** A user reports that v0.1.1 works on their iOS 16 device. This is a device report, not an independent verification of every Strava account or server endpoint. The GitHub build separately verifies compilation and package integrity.

## Install and test

Download the latest rootless DEB from [Releases](https://github.com/551UK/Strava-App-iOS16/releases). Remove the previous version if necessary, install through Sileo or Zebra, and make sure Choicy allows injection into Strava. Fully close and reopen the 422.0.1 IPA. If it crashes again, disable the tweak or remove it; send a redacted crash report rather than account credentials.

## Preferences

Copy the sample com.551uk.stravacompat.plist to /var/jb/Library/Preferences/com.551uk.stravacompat.plist via Filza, and force-close/reopen Strava after changes. The keys are Enabled, AppVersion, EnableLocalVersionCheck, SpoofHeaderVersions, SpoofIOSVersion (off by default), and IOSVersion. To isolate a crash, first set EnableLocalVersionCheck to false, then SpoofHeaderVersions to false. Disabling Enabled bypasses all hooks. Do not turn on iOS version spoofing until basic startup works.

## Build

GitHub Actions builds and validates a rootless Theos .deb from main and publishes it to Releases. This repository distributes **no Strava IPA**, and includes no premium-unlock code.

## Older 375.0.0 modified IPA

The user-supplied StravaPremium 375.0.0 IPA includes third-party `StravaPatch.dylib` and `libsubstrate.dylib`. These are **not part of StravaCompat**. `StravaPatch.dylib` references `@executable_path/Frameworks/libsubstrate.dylib` and appears connected to subscription-related modifications. Its runtime compatibility with Strava 422.0.1, distribution rights, and safety are not established. To preserve the working v0.1.1 login tweak, do not merge those unverified binaries into the public rootless release.

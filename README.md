# StravaCompat for iOS 16

Rootless jailbreak compatibility tweak for **Strava 422.0.1 on iOS 16**.

## Features

- Editable reported Strava version, default **486.0.2**, through the app's main-bundle short-version value.
- Guarded `isAppVersionValid` local compatibility check.
- Optional, separate iOS version spoof (disabled by default).
- Master Enabled switch, Restore Defaults, and the Strava Settings icon.
- Injects only into `com.strava.stravaride`.

**Version Headers has been permanently removed.** No HTTP request-header hooks or HTTP version rewriting are installed, even if an older `SpoofHeaderVersions` preference exists on the device. Strava's own request headers are passed through unchanged.

Open **iOS Settings → StravaCompat** to adjust settings, then fully quit and reopen Strava. A local compatibility check and reported app version are not a guarantee of subscriber-only route discovery or other server-controlled features.

Only the primary StravaCompat tweak is maintained in this repository. The experimental separate SearchFix development package and workflow have been removed from the current source tree. Previous code remains accessible in Git commit history if needed, but is **not included** in the new StravaCompat DEB.

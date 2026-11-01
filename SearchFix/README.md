# Strava Search iOS16 — Diagnostic Add-on

Standalone iOS 16 rootless tweak for **Strava 422.0.1**. Designed to diagnose two failures: tapping **Maps → Search locations** and opening a route, when both display **Try Again**.

## What is logged

- View-controller transitions, including route, Maps and checkout/loading screens
- Request host, method, broad category, HTTP status and response MIME type
- Network errors, including URLSession domains and codes
- GraphQL operation names where available and error **codes only** (never error messages)
- Snapshots of active network tasks and response statuses when the log is shared

**Privacy:** No URLs with paths or query strings, passwords, tokens, cookies, authorisation headers, search text, route names, precise coordinates, or raw request/response bodies are written to the log. GraphQL data is inspected in memory for safe error codes only.

## How to reproduce

1. Install with Sileo or Zebra over the earlier StravaSearch16 add-on. Keep your working StravaCompat installed.
2. Fully quit Strava and reopen it.
3. Tap **Maps → Search locations** to reproduce **Try Again**.
4. Use the floating **Share Log** / **Share Diagnostics** button to save the log.
5. Return to Maps. Tap a route (for example, the route you showed in the screenshot) and reproduce **Try Again**.
6. Tap **Share Log** again. Send the second file, which contains both tests.

The sharing button stays available even if Strava renders Try Again using a view that cannot be inspected by UIKit.

If the button doesn't appear, find the log under Strava's own sandbox at:
`/var/mobile/Containers/Data/Application/<Strava UUID>/Library/Caches/StravaSearch16/diagnostics.txt`.

The existing MapKit fallback code is retained but deliberately **disabled** during diagnostics. This diagnostic add-on neither modifies the StravaCompat login code nor fixes the backend by itself. Use the log to determine the failure before changing requests.

## Build

Run `cd SearchFix && make clean package FINALPACKAGE=1` with Theos and an iOS 16 SDK. Add-on ID: `com.551uk.stravasearch16`.

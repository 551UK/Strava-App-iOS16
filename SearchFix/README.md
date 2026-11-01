# Strava Search iOS16 v0.7.0 — Overlay and public route diagnostics

This updates the **existing** `com.551uk.stravasearch16` package. Keep StravaCompat → **Version Headers OFF**, as that corrected the initial Try Again failures. The existing login tweak is unchanged.

## What's new

The v0.6.0 controls were attached to the main Strava UIWindow and could be hidden by a separate full-screen SwiftUI checkout window. v0.7.0 uses a separate **touch-transparent overlay UIWindow**, above native modal presentations, without taking the key window away from Strava. It provides:
- **Share Log** at the top right, regardless of whether a trial offer is open.
- **Public routes (N)** at the top left; visible even when **N=0**. Tapping it explains when no accessible Strava public-route links were discovered.
- **Close offer** when a Checkout/Upsell controller is detected. This is an explicit user-invoked dismiss action like tapping Strava's own X. It does not grant access to subscriber-only content and may return to the map.

The logger now emits `PUBLIC_ROUTE_SCAN nodes=N valid=N missing=N rejected=N` each time Strava's `SuggestedRoutes` GraphQL response arrives. Only **counts** are logged, never route titles or URLs. The previous v0.6.0 viewer silently filtered URLs, preventing a reliable diagnosis.

## Device test

1. Install v0.7.0 over SearchFix v0.6.0; keep StravaCompat installed and **Version Headers OFF**.
2. Restart Strava; choose Maps → Routes and wait for suggested routes to populate.
3. Tap any visible route or the search field.
4. The overlay should show **Share Log** and **Public routes (N)** above the trial offer. Tap Public routes: if N is positive, select an actual Strava HTTPS route URL; if zero, the app reports no usable public link.
5. Share the log; look for `HUD_READY` and `PUBLIC_ROUTE_SCAN` as well as the checkout controller.

This is a **diagnostic/public-route access experiment**, not a paid subscription bypass or proof that a free account can use subscriber-only route discovery. It does not hide checkout automatically, alter entitlements, intercept purchase receipts, rewrite route responses, or create fabricated route links.

## Earlier Premium 375 comparison

The user-provided `StravaPremium-375.0.0.ipa` includes `StravaPatch.dylib` with a MobileSubstrate hook and an NSURLSession data task method selector, plus a trial-product identifier. This indicates network/subscription instrumentation but not a proven modern route-viewing implementation. Its binary has no obvious exported route-specific hook. Copying its patch into 422.0.1 would be unreliable and may cause issues with legitimate purchase state.

## Logs
`Library/Caches/StravaSearch16/diagnostics.txt` within the Strava app container. No auth headers, credentials, request/response body text, precise coordinates, or full route URLs are logged.

Build with `cd SearchFix && make clean package FINALPACKAGE=1`.

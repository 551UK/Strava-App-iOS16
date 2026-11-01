# Strava Search iOS16 0.6.0 — Public-route test

This is the existing rootless `com.551uk.stravasearch16` diagnostic tweak for Strava 422.0.1 on iOS 16. **Leave StravaCompat's Version Headers OFF**; that was the proven fix for the original Try Again screens. This add-on does not change account entitlements or subscriptions.

## What this version tests

The **SuggestedRoutes** GraphQL query in both the older 422.0.1 and newer 487.0.0 IPAs explicitly requests a `routeUrl` and route title for each suggested route. Your diagnostics confirm that this GraphQL response returns multiple routes. On receipt, this build collects any real **HTTPS Strava public-route URLs** already present in that response. It does **not** fabricate IDs, translate subscription state, or unlock a subscription feature.

If Strava displays the free-trial checkout screen and at least one URL is usable, a **View shared routes** button appears near the lower left. Tap it, select the route by its title and distance, and it opens in a Safari view inside the app. Strava's server determines what the free account can view; subscribers may still have additional controls. If no public URL is returned, no viewer button appears. No bypass is attempted.

The floating **Share Log** remains available. The old diagnostics and experimental version-only bridge remain in the add-on, though with **Version Headers disabled** no matching modified headers should be present.

## Steps

1. Install version 0.6.0 over 0.5.0. Keep StravaCompat installed with **Version Headers OFF** and local version check ON.
2. Force-quit and reopen Strava, select Maps, and let the suggested routes populate.
3. Tap the specific suggested route; on the trial screen look for **View shared routes** at bottom left.
4. If available, select the same route in the list and check whether its public page opens and permits viewing.
5. Share `diagnostics.txt` regardless, noting whether the button appears, whether a browser opens, and whether the page is accessible.

This is a proof-of-concept for **public route viewing**, not a native route-detail restoration or guarantee that every suggested route is free. The subscription purchase path is untouched.

## Premium IPA comparison

The previously uploaded `StravaPremium-375.0.0.ipa` is an older 375.0.0 build (iOS 15 minimum), with `StravaPatch.dylib` and `libsubstrate.dylib` injected. Static inspection finds URLSession interception and subscription/trial product strings in the patch, but it has no obvious route-specific hook symbols. This **does not establish** that the premium-patched client could access present-day routes. Its binary is not used or copied in this test build.

## Privacy

Stored logs include network host, request type, HTTP code and predefined response structure; never full request/response bodies, route names, precise coordinates, URLs or authentication secrets. Shared-route titles and URLs are kept only in process memory for the chooser and cleared on app exit.

Source: `SearchFix/Diagnostics.xm`, `SearchFix/SharedRoutes.m`, `SearchFix/Bridge.m`.

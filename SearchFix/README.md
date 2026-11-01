# Strava Search iOS16 — 0.8.0 downloaded-route preview

This updates the existing rootless package **com.551uk.stravasearch16** for Strava 422.0.1 on iOS 16. Keep **StravaCompat → Version Headers OFF**; that setting was confirmed to resolve the original Try Again errors. The login tweak is unchanged.

## 0.8.0: use route geometry already downloaded by Strava

Both supplied Strava 422.0.1 and Strava 487.0.0 decrypted app binaries include the **SuggestedRoutes** GraphQL query. It requests `routeUrl`, `title`, `length`, and `routePolylineData { legs { paths { polyline { data } } } }`. Your logs show 5 and 15 SuggestedRoutes nodes being delivered.

Previous versions assumed `routeUrl` must be an HTTPS public web URL and rejected everything else. The zero count therefore did **not** mean there were no suggested routes. Version 0.8.0 reads the encoded polyline points **already included in the successful response**, decodes them locally using the standard precision-5 polyline format, and draws them on an independent read-only **MapKit** map. It does not request further subscriber-only route data or modify checkout/entitlements.

The transparent overlay (above Strava modal screens) shows **Route previews (N)** at top left and **Share Log** at top right. Tap Route previews to choose from the downloaded routes, then view the path on a native MapKit map. If a route has no decodable geometry but a valid public Strava link, it can be opened in the Safari view. Strava's original offer may still appear underneath; use Strava's native X if needed. The redundant "Close offer" control has been removed.

The diagnostic log now includes `ROUTE_PREVIEW_SCAN nodes=N geometry=N publicLinks=N unrecognisedLinks=N missingLinks=N accepted=N`. No route titles, coordinates or URL contents are logged.

## Testing

1. Install 0.8.0 over 0.7.0. Keep StravaCompat and keep **Version Headers OFF**.
2. Force-close Strava, reopen and let Maps suggested-route results load.
3. Look for **Route previews (N)** on the overlay. Tap to see a list and choose a route.
4. Check that the displayed path and approximate distance match the selected listed route.
5. Test tapping the usual card and Search locations, then share the diagnostic log.

**Limitations:** This is a read-only preview of data Strava already returned; it is **not** a native route detail view, route navigation, downloading, or a subscription bypass. It does not guarantee that routes are available in every response. The app's checkout presentation is intentionally left intact.

## Relevant IPA comparison

- Strava 422.0.1 and 487.0.0 both contain a `FlyoverGeometryQuery` accepting a `routeUrl`, and both contain the SuggestedRoutes geometry fields. No evidence establishes that replaying `FlyoverGeometryQuery` succeeds for a free account.
- Older StravaPremium 375.0.0 bundles `StravaPatch.dylib` with networking and subscription-related hooks. There is no demonstrated route-specific fix we can safely copy from it.

## Diagnostics location

Strava container → `Library/Caches/StravaSearch16/diagnostics.txt`.

Build: `cd SearchFix && make clean package FINALPACKAGE=1`.

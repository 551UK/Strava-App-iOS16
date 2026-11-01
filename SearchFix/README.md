# Strava Search iOS16 v1.0.0 — native route navigation experiment

StravaCompat's **Version Headers must stay OFF** (this previously fixed Try Again). This is a separate SearchFix package; the working login tweak is unchanged.

## Finding from *all three supplied decrypted IPAs*

Strava **375.0.0, 422.0.1, and 487.0.0** each register these route-detail navigation patterns:

- `strava://route/suggested/:id/view_details`
- `strava://route/:id/view_details`
- `strava://routes/:id`

The **422 and 487** dynamic-map Swift action structures also declare distinct closures `openRouteDetailPage(String)` and `showUpsell(Surface)`. This confirms a native detail pathway exists separately from the subscription prompt. It **does not** establish that the server permits every route detail for a free account.

## What 1.0.0 changes

- The existing overlay changes **Route previews (N)** to **Strava routes (N)** and lists all actual SuggestedRoutes records, even when previous URL/geometry filters rejected every entry.
- For a `routeUrl` that is already a genuine Strava internal link, or an explicitly recognised relative native route path, tapping it sends that link to the **Strava app's own URL router**. No ID is fabricated.
- For known public Strava route URLs, opens the public page (or a map preview if geometry exists).
- Route polyline decoding now supports either `routePolylineData.legs[].paths[].polyline.data` (the 422/487 shipped GraphQL query) **or** `legs[].paths[].polyline.data` (observed in external 422.0.1 route-response research).
- If a routeUrl is only an opaque token and there is no decodable geometry, the UI explains the limit rather than sending an invented URL.
- `NATIVE_ROUTE_SCAN` logs **counts only**: native route links, relative route links, public links, opaque values, field shapes, and geometry. No route names, coordinates, route identifiers, or URL content is saved in the log.
- Existing checkout call-stack tracing remains intact.

This experiment **does not modify an account's subscription status, StoreKit receipts, API authorization, or the original checkout UI**. Strava may legitimately route the same native URL to a trial offer for a free account.

## How to test

1. Install v1.0.0 over v0.9.0. Leave StravaCompat → Version Headers OFF.
2. Fully quit and relaunch Strava. Go to Maps → Routes and let the route cards load.
3. Tap **Strava routes (N)** at the top. Select a route. If the `routeUrl` is an internal Strava link, this should ask Strava's own router to show its native detail page; if the URL is opaque, the app explains why a direct route link can't be constructed.
4. Separately tap the original route card and the Search locations field. They may still display the trial offer.
5. Share the log, specifically the `NATIVE_ROUTE_SCAN` and `CHECKOUT_FRAME` records.

The implementation is a native route-navigation **test**, not a verified full subscription-free route feature. Nothing from the older StravaPremium 375 patch was copied or used to forge access.

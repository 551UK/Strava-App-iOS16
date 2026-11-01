v1.0.0 — test Strava's own route-detail destination rather than replacing its checkout.

Static analysis of all three supplied IPAs (375/422/487) identified:
`strava://route/suggested/:id/view_details`, `strava://route/:id/view_details`, `strava://routes/:id`.
The 422 and 487 binaries also have separate `openRouteDetailPage` and `showUpsell` callbacks.

- The overlay lists **Strava routes (N)** based on actual SuggestedRoutes records instead of hiding all records that lack a public https link.
- Opens genuine Strava deep links returned by the API with Strava's own URL router. No route IDs are invented.
- Accepts two observed polyline response shapes for the optional read-only map preview.
- Logs only privacy-safe field-shape counters via `NATIVE_ROUTE_SCAN`.
- Retains checkout call-stack tracing and Share Log.
- Does not spoof subscription state, modify responses or automatically hide checkout; free-account server restrictions still apply.
- **Version Headers OFF** remains necessary in StravaCompat. This is an unverified on-device experiment.

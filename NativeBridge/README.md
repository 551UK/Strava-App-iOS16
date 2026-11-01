# Strava Native Bridge v1.4.0 — experimental

Separate iOS 16 rootless add-on (`com.551uk.stravasearch16`) for Strava 422.0.1. The working **StravaCompat v0.3.0** login tweak and the `main` branch stay untouched.

## Nearby walking routes

- Tapping the Strava search field and choosing a place now opens a route browser centred on that place, instead of a location-only preview.
- The on-screen **Nearby walks** button opens the same browser around the phone's location (with normal iOS location permission).
- **Swipe up** on the browser's bottom handle to see available walks. Select a walk to display its path on the map.
- Previously received Strava route geometry is only listed if it actually falls within 8 km of the selected area. An old response from another city is not presented as nearby.
- When Strava has no locally available route geometry, the browser searches for genuine nearby destinations and calculates pedestrian **out-and-back** routes using Apple's MapKit walking-directions service. These are clearly marked **Apple Maps walking directions**, not Strava suggestions.
- Apple Maps directions may not return routes in every area; no lines or distances are invented. Selecting a MapKit walk can open walking directions in Apple Maps.

## Limits and testing

This restores useful location-specific *walking route discovery* as a fallback, **not** Strava's original server-powered Suggestions UI or Premium route generation. A real Strava location-based SuggestedRoutes request has **not** been reverse-engineered or unlocked. The swipe-up panel is inside the add-on's MapKit browser; it is not the native Strava sheet.

No receipt, entitlement, login-token, or HTTP-header changes. This source has not yet been tested on an iPhone. Build validation alone does not prove that MapKit results, GPS permission, and UI gestures work on-device.

Install this package **over** Native Bridge 1.3.0; do not install both simultaneously. Keep StravaCompat v0.3.0 installed.

v0.7.0 — diagnostic UI above Strava modal offers.

- Fixes hidden **Share Log** and **Public routes (N)** controls by placing them in a transparent high-level UIWindow. Empty overlay areas pass touches through.
- Logs `PUBLIC_ROUTE_SCAN nodes/valid/missing/rejected` so we can establish whether Strava's SuggestedRoutes response contains public route URLs.
- Adds **Close offer**, a manual dismiss action equivalent to the X on the trial offer. This does not unlock subscription features.
- Keeps the native app, StravaCompat, purchase state and permissions unchanged. **Version Headers must remain OFF.**
- The previously supplied Premium 375 IPA was inspected as a reference, but its injected network hook does not establish present-day route availability and has not been copied.
- Device behaviour has not yet been verified; if overlays remain absent, use Filza to export the diagnostics log.

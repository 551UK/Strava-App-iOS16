# Strava Native Bridge v1.3.0 — experimental

This is a **separate rootless tweak** (`com.551uk.stravasearch16`) developed only on the `native-bridge` branch. The working StravaCompat v0.3.0 source, Settings, and release on `main` are untouched.

### What changed
- Recognises Strava's internal `routing/suggested_routes` route links, which were excluded from the earlier parser, plus the existing `route`/`routes` destinations. Uses route identifiers only when actually supplied by Strava.
- The native Strava search bar tap, when it otherwise leads to checkout, can open a **MapKit-based location-search fallback** (not the original Swift location search). This does not require a trial.
- The normal route tap, when it otherwise leads to checkout, opens Strava's list of already-downloaded suggested routes. Selecting a recognised native link attempts Strava's own URL navigation first; when the returned data has no valid deep link, the read-only MapKit route viewer remains the fallback.
- The draggable **Navigation test: On / Off** switch lets users return to Strava's normal checkout screens. The existing diagnostics and GPS following remain.

### Boundaries
Opening Strava's route-detail endpoint is an experiment. Strava may independently require an active subscription for data or activity recording. This tweak neither grants entitlement nor intercepts receipts; it does not modify HTTP request headers. It has **not been verified on a device**.

Install v1.3.0 over the old SearchFix v1.2.0 package, not alongside it. Keep StravaCompat v0.3.0 installed. The compatibility package is completely separate and unchanged.

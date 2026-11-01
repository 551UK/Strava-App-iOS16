**StravaSearch16 v1.2.0 — original navigation A/B tracing**

- Adds a **Trial popup: Hidden / Shown** overlay switch. Default Hidden skips presentation of Strava's CheckoutLoadingView, and logs `CHECKOUT_UI_SUPPRESSED`. Switch to Shown for normal Strava trial/purchase UI. Neither mode fabricates trial/subscription status.
- Adds `FLOW_PRESENT`, `FLOW_PUSH`, `FLOW_FRAME` records to trace route/location search and navigation-controller code paths, particularly **after a genuine free trial**, while excluding search text, route IDs, auth data and precise location.
- Keeps `CHECKOUT_FRAME` and GraphQL/network diagnostics to compare free vs genuine trial flows.
- Retains v1.1.0's read-only map route follower and draggable overlay.
- The free account's Search locations field might still do nothing when the offer is hidden: that would show the route-detail continuation was never invoked, not that a subscription was unlocked.
- **Version Headers OFF** in StravaCompat remains essential; StravaCompat itself is unchanged.
- Not device-validated; compiled package only.

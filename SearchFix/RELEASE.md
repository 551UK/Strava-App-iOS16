**v0.8.0 — read-only downloaded route geometry preview**

- Fixes the earlier `Public routes (0)` limitation: Strava's `routeUrl` need not be a public browser link, but the SuggestedRoutes response also contains encoded route line data.
- Decodes `routePolylineData.legs[].paths[].polyline.data` locally and displays routes in a MapKit viewer reached through **Route previews (N)** on a floating overlay.
- Keeps **Share Log** and logs `ROUTE_PREVIEW_SCAN` counts so missing geometry can be diagnosed.
- Removes the redundant Close offer button; Strava's own X remains.
- No fake free trial or subscription, checkout tampering, new API calls, injected purchases, or network-response rewriting.
- The original StravaCompat tweak is unchanged; **Version Headers must remain OFF**.
- This build has passed automated compilation only. It is not yet tested on a device and does not restore subscriber-only route navigation.

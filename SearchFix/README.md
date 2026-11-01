# StravaSearch16 v1.0.1 — unobstructed route tools

This fixes an issue identified from the user's 03:40 iOS16 screenshot: the `Strava routes (15)` and `Share Log` overlay buttons were attached across the native Strava **Search locations** field, making the underlying field difficult or impossible to tap.

The two overlay controls now appear together on the **right side of the map**, below the native search and filter controls. They are draggable up/down as a pair using a swipe or drag on either button. This leaves the native search box accessible. The controls stay above Strava's modal views, but empty space is touch-transparent.

**Strava routes (N) is an actual clickable button from SearchFix**. Tap it (do not just tap the native orange route lines) to select the real SuggestedRoutes records downloaded by Strava. The selected record is handed to Strava's internal deep-link router **only when the returned routeUrl is already a recognised Strava route link**. This may still open checkout if Strava gates the page. No route IDs or subscription states are fabricated.

All existing v1.0.0 networking, route navigation, call stack logging, dual-schema geometry preview and read-only public-route access logic are unchanged. Separate StravaCompat remains untouched.

## Test

1. Install v1.0.1 over v1.0.0. Leave **StravaCompat → Version Headers OFF**.
2. Reopen Strava Maps and verify Search locations at the top is now unobstructed. The two small SearchFix buttons should be on the **right-hand map area**.
3. Tap the **Strava routes (N)** button. If routes are listed, tap one and note whether it opens a native detail page, a browser, a preview, an unsupported-URL notice, or another trial offer.
4. If the controls cover a part of the map you need, **drag either button up or down**. This moves the pair.
5. Share the log if the chosen route does not open. The relevant lines begin `NATIVE_ROUTE_SCAN`, `CHECKOUT_PRESENT` or `CHECKOUT_FRAME`.

**Important:** The v1.0.0 screenshot showing 15 records and orange lines proves Strava has route records and displays polylines, **not** that native route-detail navigation was fixed. This is a UI-only convenience update, not a verified backend repair.

# Strava Search iOS16 v1.1.0 — follow a downloaded route with GPS

The previous v1.0.1 MapKit **Route preview** displayed the geometry correctly, but had no Start/Follow control. This release adds a self-contained **Start following route** button inside that same map viewer.

## What starting a route does

- Requests the iPhone's normal **While Using the App** location authorization if needed. Never spoofs location or bypasses permission.
- Shows the user's blue GPS dot, uses MapKit follow-with-heading mode and updates location on the displayed path.
- Calculates the nearest segment on the **actual Strava polyline already returned by SuggestedRoutes**, and displays approximate remaining route distance and off-route deviation (metres).
- A **Stop following** button stops active GPS updates. Closing the screen also stops the viewer's location updates.
- Places the title in the safe area and adds a bottom status/button panel, correcting the prior screenshot's overlapping title and navigation elements.
- Keeps map and route records in local process memory. No GPS samples or coordinates are saved to the tweak's diagnostics.

## Limits

**Following is a read-only, self-contained GPS guide inside the SearchFix MapKit viewer**, not Strava's native subscriber-only route navigation. It does **not** start an activity recording, upload a route, create turn-by-turn instructions, provide voice guidance, or request access to subscription-only server APIs. The status is approximate (especially on overlapping loops or complex route branches), and GPS/map guidance should not be used as a sole source of safety-critical directions. The map updates while the viewer is active and the OS allows access.

## Test

1. Install v1.1.0 over v1.0.1. Leave **StravaCompat → Version Headers OFF**.
2. Open Maps, use the unobtrusive **Strava routes (N)** button, choose a route.
3. On the map, tap **Start following route**. Approve While Using location access if prompted.
4. The map should centre on the blue location marker and show your approximate deviation from the path and remaining distance. Press **Stop following** to end guidance.
5. If you need native Strava recording instead, it is **not included** in this viewer; Strava's route-detail feature may still require a subscription.

All of v1.0.1's route data extraction, deep-link routing attempt, diagnostics, and draggable floating buttons remain unchanged.

SearchFix v1.0.1 — fixes floating buttons obstructing Strava's search field.

- Moves **Strava routes (N)** and **Share Log** into a compact, **draggable** pair on the right-hand map area.
- Both buttons remain clickable; dragging either moves them together without taking control of the underlying Strava screen.
- Preserves v1.0.0 route-list extraction, native deep-link experiment, geometry preview and checkout caller tracing.
- Does not alter StravaCompat login, server entitlement, purchase flow or Strava's subscription UI. Leave **Version Headers OFF**.
- Compiled build; native route-detail opening still requires device verification.

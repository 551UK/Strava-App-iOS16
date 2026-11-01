v1.1.0 — user-requested **Start following route** mode.

- Adds a Start/Stop GPS-following control to the downloaded-route MapKit preview, with the blue location dot, heading follow, approximate remaining distance and off-route distance.
- Fixes overlap between the title and the navigation bar using safe-area layout; a bottom status panel contains the control.
- Requires normal iOS location permission; location is not fabricated and no coordinates are stored in diagnostic logs.
- Keeps the original Strava route extraction, checkout trace and draggable overlay. Separate StravaCompat unchanged. **Version Headers must stay OFF**.
- The feature is independent MapKit route following, **not native Strava activity recording or subscriber navigation**. It has only been compilation-tested, not field-tested.

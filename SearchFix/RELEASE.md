Diagnostic prerequisite for the planned native Strava search/route bridge. This is **not a completed bridge or a confirmed fix**.

Install over StravaSearch16 0.3.0, keep StravaCompat installed, fully quit Strava, then reproduce Maps search and tapping a route. Share the log using the existing button.

Adds static endpoint labels and bounded response-shape summaries, including session-delegate responses that 0.3.0 missed. No raw request/response bodies, coordinates, route names, authentication headers or query text are logged. Native Strava screens remain in place.

Both supplied IPAs were examined: 422.0.1 (49113, iOS 16) and 487.0.0 (55612, iOS 17). The newer app changes geocoding clients, but existing logs cannot establish the failing request or decoder contract. A targeted bridge requires that missing runtime evidence.

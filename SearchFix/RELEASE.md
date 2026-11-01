Experimental public-route viewer for Strava 422.0.1 on iOS 16. This **does not unlock subscription features** and has not been device-tested.

- Captures `routeUrl`, title and length already returned by Strava's successful SuggestedRoutes query; never invents links.
- If public Strava HTTPS route URLs are available, shows a **View shared routes** button on the checkout/trial screen. Select a route and view its public page in the built-in Safari controller.
- Keeps diagnostics and StravaCompat unchanged. **StravaCompat → Version Headers must remain OFF**, which resolved the earlier Try Again errors.
- If Strava returns no public route URLs or restricts their viewing, no content is bypassed. Share the log and report whether the button appears.
- The older uploaded StravaPremium 375.0.0 IPA was inspected; its injected patch contains subscription/trial-related networking code but no demonstrated modern route-access fix.

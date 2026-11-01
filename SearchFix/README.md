# Strava Search iOS16 — Experimental Native Bridge v0.5.0

This builds on the *existing* StravaSearch16 package for Strava 422.0.1 on iOS 16. The user's separate StravaCompat tweak (login compatibility) is unchanged.

## Why this is a controlled experiment

Comparison of the supplied decrypted Strava 422.0.1 and 487.0.0 IPAs identified newer geocoding and route-detail implementations, but the older `SuggestedRoutes` GraphQL list succeeds and `routes/details_v2` exists in both builds. Therefore, blindly rewriting endpoints or importing 487's Swift classes into iOS 16 is not justified.

StravaCompat currently substitutes a newer version **in all selected network headers**, which may cause the service to select responses unsuited to 422.0.1. This version adds a narrowly targeted request-identity adapter. It attempts to restore the actual `422.0.1` client version **only** on route, search/geocoding and checkout endpoint requests, including corresponding GraphQL operations. Authentication/login requests are not targeted. It does not change an account's subscription entitlements.

`BRIDGE_IDENTITY` log entries report how many eligible header values were found and whether the changes survived other installed header hooks. If `matched=0`, this experiment did **not** alter that request. If `matched>0` but `applied=0`, another hook is likely overriding it. These counters are intentionally explicit; installing the build alone **does not prove a repair**.

## Testing

1. Install v0.5.0 over the existing SearchFix add-on; keep StravaCompat installed.
2. Force-close Strava and launch normally.
3. Test Maps → Search locations, clicking a visible suggested route, and the free-trial screen.
4. Use **Share Log** to export `diagnostics.txt` after all three failures or successes.
5. Compare UI behaviour and `BRIDGE_IDENTITY` / `HTTP_` lines to the previous v0.4.0 log.

**Rollback:** uninstall only `com.551uk.stravasearch16`. To disable just the bridge, use Filza to create an empty file `Library/Caches/StravaSearch16/disable-bridge.flag` inside Strava's app data container and restart the app.

This is experimental request-version reconciliation, **not a verified route/search fix**. It does not fake entitlements, replace the Strava interface, or alter response content. All logs omit passwords, auth headers, URL query text, route titles, and coordinates.

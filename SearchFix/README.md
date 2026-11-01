# Strava Search iOS16 — Diagnostics

A separate diagnostics add-on for **Strava 422.0.1 on iOS 16**, designed for two failures: **Maps → Search locations → Try Again** and **tapping a route → Try Again**.

**What it records**
- Screen controller transitions and the presence of the **Try Again** error.
- Network request host, broad category (routes, searches, maps, GraphQL), HTTP status, transport error domain and numeric code.
- WebView load attempts and task completion results, including delegate-based URLSession tasks where observable.

**Privacy:** No passwords, tokens, cookies, authorization headers, search text, route titles, precise coordinates, request or response bodies, or URL query parameters are logged. The diagnostic text file is stored in Strava's own app container.

**How to test**
1. Install the standalone .deb with Sileo or Zebra, alongside your working StravaCompat.
2. Fully close and reopen Strava.
3. Tap **Maps → Search locations** and reproduce **Try Again**.
4. Tap **Share Diagnostics** on that error screen and save/send `diagnostics.txt`.
5. Close the error, tap a route and reproduce the second **Try Again**.
6. Use **Share Diagnostics** again; the file will contain both failures.

The button only appears while a detectable **Try Again** screen is visible. If it does not appear, find the file using Filza under:
`/var/mobile/Containers/Data/Application/<Strava UUID>/Library/Caches/StravaSearch16/diagnostics.txt`.

The MapKit search fallback code is retained but **disabled by default** so it cannot hide the original error while capturing evidence. This build does not yet repair the original Strava search/route service, and it does not change StravaCompat's login hooks.

Build: `cd SearchFix && make clean package FINALPACKAGE=1` with Theos and iOS SDK.

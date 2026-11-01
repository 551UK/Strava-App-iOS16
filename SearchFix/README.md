# Strava Search iOS16

Separate rootless compatibility add-on for **Strava 422.0.1 on iOS 16**.

If tapping **Maps → Search locations** immediately produces a blank **Try Again** screen, the tweak detects the failed search after that specific tap and presents a native iOS MapKit location search. You can autocomplete places, view a map pin, copy latitude/longitude, and open the location in Apple Maps. This avoids the failing Strava search screen rather than pretending that Strava's older API works.

The addon deliberately does **not** alter StravaCompat, login, authentication headers, route subscriptions, or Strava's server responses. It does not currently hand selected coordinates back into Strava's Mapbox map; that integration needs an additional, app-specific test.

Install through Sileo or Zebra. Ensure Choicy allows injection for Strava, then fully close and reopen it. Open the regular Maps → Search locations control. On the exact Try Again failure, MapKit search appears. Use Done to return to the original app.

The source targets only `com.strava.stravaride` and is packaged as `com.551uk.stravasearch16`. For compile: `make clean package FINALPACKAGE=1` with Theos and the iOS SDK installed.

**Testing status:** built against the Strava 422.0.1 user-provided IPA's known screen labels; on-device behaviour is not verified yet. Please test first before relying on this for offline navigation.

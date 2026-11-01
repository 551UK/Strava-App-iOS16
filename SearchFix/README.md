# StravaSearch16 v1.2.0 — compare navigation before and after a genuine trial

**Purpose:** determine what Strava 422.0.1 does *after* a trial becomes active, instead of speculatively recreating the route viewer or interpreting the checkout popup as a broken API.

## What is new

- **Trial popup: Hidden** — a third, draggable overlay control alongside **Strava routes** and **Share Log**. It defaults to **Hidden**. When a `Checkout.CheckoutLoadingView` attempts to present, the tweak logs the caller and suppresses the UI presentation, leaving Strava's underlying screen visible. This does **not** call a route-detail continuation, grant subscription access, change a server response or unlock anything.
- **Trial popup: Shown** — tap the same control to allow native checkout/trial screens normally. This is essential if you voluntarily decide to begin an actual trial through Strava. The control state resets to **Hidden** on a force-quit/relaunch; be sure to switch it to **Shown** before accessing native checkout.
- **FLOW_PRESENT**, **FLOW_PUSH**, and **FLOW_FRAME** — new bounded call-stack tracing of native location/search/route/navigation controller presentations and navigation pushes, including in-process Mach-O-relative code offsets. Compare which native screen opens *after* a genuine trial, vs. the earlier free-account flow. Logs deliberately omit searches, locations, route IDs, credentials and response bodies.
- Existing `CHECKOUT_PRESENT`, `CHECKOUT_FRAME`, `NATIVE_ROUTE_SCAN` and `UI_CONTROLLER` logging remains.
- Original downloaded-route MapKit GPS-follow mode from 1.1.0 remains, as do the draggable overlay controls. Login tweak StravaCompat has **not been changed**.

## What this does not do

Hiding the checkout UI is purely a **presentation experiment**. If the free account lacks route discovery access, the Strava search field and route selection might remain in the prior UI or do nothing. That is **not** a failure of this test; it means the native client never called the route-detail continuation. An independent read-only MapKit route follower is available separately in `Strava routes (N)`. This add-on does not spoof entitlements, trial records or StoreKit receipts, and does not fabricate route identifiers or modify purchases.

## How to capture useful A/B logs

1. Install this add-on over v1.1.0; keep StravaCompat installed with **Version Headers OFF**.
2. **Free account control:** restart Strava, leave **Trial popup: Hidden**, tap **Search locations**, tap a suggested route, then **Share Log**. This records the suppressed checkout and any attempted continuation without starting a trial.
3. **Optional genuine trial:** if you personally choose to use Strava's offer, tap **Trial popup: Hidden** once to change it to **Trial popup: Shown**; then use Strava's ordinary trial screen. Review the actual renewal terms and cancel before billing if desired. Only the user can authorise a subscription.
4. **Genuine-trial comparison:** force-close/reopen Strava (which resets the overlay to Hidden, but **does not** alter your real subscription state). Test Search locations and the **same route** using the *native Strava buttons*, not our `Strava routes (N)` viewer, then tap Share Log. These traces should expose the actual location-search controller, route-detail controller, navigation destination, and any additional GraphQL requests permitted to a trial account.
5. Send the diagnostic file from both conditions and describe which button was pressed at each test. The log is in Strava's sandbox under `Library/Caches/StravaSearch16/diagnostics.txt`. It rotates at 1 MB, so share each log before it rolls if you need separate sessions.

**Important:** Use actual Strava trial access only if you want it; testing the popup suppression does not require one. Trial expiry or billing cannot be controlled by the tweak. No data is saved or sent automatically by this tweak.

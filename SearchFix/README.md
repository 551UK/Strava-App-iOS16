# Strava Search iOS16 v0.9.0 — find the checkout caller

The screenshot from Flex confirms `STRVTabBarController.presentedViewController` is `UIHostingController<Checkout.CheckoutLoadingView<...>>`. It establishes which view is shown, but **not** the Swift/Objective-C method that requested it.

## New instrumentation

On every presentation of `CheckoutLoadingView`, this build writes a bounded backtrace:

- `CHECKOUT_PRESENT`: presenter, destination, current tab/nav controller and visible view class
- `CHECKOUT_FRAME`: in-process image name, Mach-O **image-relative instruction offset**, and static symbol if exported
- `CHECKOUT_PRESENT end`: trace delimiter

These offsets can be matched against the user-supplied **decrypted Strava 422.0.1 executable** and compared with its corresponding route/upsell implementation in 487.0.0. Capturing a call stack at the actual presentation time is more useful than scanning static class names or looking at Flex's generic hierarchy alone. Up to 14 presentations and 32 frames each are recorded to bound the log.

The route-preview experiment from 0.8.0 remains, including `ROUTE_PREVIEW_SCAN`. A zero counter can indicate the free account received metadata without decodable geometry; logs reveal which fields are missing.

**No account entitlement, response, route navigation or checkout state is modified.** The new hook forwards to the original UIKit method. There is no fabricated trial, no purchase interception and no suppression of subscription UI. The separate StravaCompat login tweak is unchanged.

## Testing

1. Install v0.9.0 over v0.8.0. In Settings → StravaCompat, leave **Version Headers OFF**.
2. Force-close and reopen Strava, go to Maps, and tap one suggested route. Let the trial offer appear.
3. Tap **Share Log** on the overlay and send `diagnostics.txt` (no more Flex screenshots needed for this stage).
4. Look for the `CHECKOUT_FRAME` section and `ROUTE_PREVIEW_SCAN` entries. These identify the call site and whether route geometry is available.

Diagnostic file: inside Strava sandbox, `Library/Caches/StravaSearch16/diagnostics.txt`.

This is a tracing build, not a completed native route viewer. The trial screen may still appear. Read-only MapKit previews depend on geometry actually returned by Strava.

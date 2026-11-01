v0.9.0 — trace the Strava route-to-checkout call site.

- Instruments UIKit `presentViewController:` only when a `CheckoutLoadingView` is being presented.
- Logs the presenting/visible controller and a bounded backtrace of Mach-O-relative offsets and static symbols, for comparison against decrypted 422 and 487 binaries.
- Preserves the 0.8.0 read-only `Route previews (N)` experiment and the Share Log overlay.
- **Does not suppress checkout**, modify subscription/trial entitlements, forge responses or alter StravaCompat.
- Keep **Version Headers OFF**. Reproduce once by tapping a route and use Share Log to send the diagnostics. Not yet device-confirmed.

# Bridge investigation

Inspected the supplied decrypted ARM64 executables (LC_ENCRYPTION_INFO_64 cryptid=0):

| App | Build | Minimum iOS |
| --- | --- | --- |
| 422.0.1 | 49113 | 16.0 |
| 487.0.0 | 55612 | 17.0 |

422 contains `search/searchbox/v1/suggest`, `search/searchbox/v1/retrieve/`, and `geocoding/v5/mapbox.places/`. 487 contains GeocodeEarthGeocoder, MapSearchGeocoder, GeocoderHTTPClient, autocomplete, reverse_geocode, and get_coordinate. These establish implementation differences, not a verified request mapping or proof of a retired server endpoint.

Both contain the SuggestedRoutes GraphQL operation. The newer query adds themed-image dimensions, media IDs and path surface/length fields. The old query remains a subset; static inspection does not establish that these additions fix any failure.

The supplied diagnostics(2).txt shows SuggestedRoutes HTTP 200, search HTTP 200, checkout HTTP 412, other HTTP 403, and repeated CheckoutLoadingView presentation. HTTP 200 alone does not establish GraphQL success, and broad categories do not identify which endpoint fails. The old diagnostic inspects JSON only on completion-block tasks; delegate tasks expose statuses but not body shape.

0.4.0 therefore captures predefined JSON field types/counts and static endpoint labels, including compatible NSURLSession delegates. No request rewrite is justified yet. Do not claim subscription state, server authorisation, route access or login has been repaired. No app binary or credentials are committed.

Next: reproduce search and route taps, inspect BODY_SHAPE/GRAPHQL_ERRORS with endpoint labels, then implement only the proven request/response translation while preserving native UI.

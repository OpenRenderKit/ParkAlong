# Map performance evidence — 24 August 2026

All parking-rule tests and measurements were run with `TZ=Australia/Melbourne` on an iPhone 17 Pro iOS 26.5 simulator using Xcode 27 beta (`27A5237l`). The bundled statewide catalog contains 34,023 records and is 22,546,415 bytes; the historical availability file is 48,303,231 bytes.

## Baseline

The baseline full simulator suite passed, but exposed a severe startup cost:

- 94 unit tests plus 16 UI tests: 173.362 seconds total.
- `testGeneratedVictorianCatalogDecodesFromAppBundle`: 23.659 seconds.
- A focused real-catalog measurement reported `bundled_catalog_decode_seconds=23.25246475`.
- Eight moving Melbourne street-view queries over the decoded catalog took 0.545419042 seconds and repeatedly walked the full catalog.

The decoder was constructing multiple `ISO8601DateFormatter` objects for every decoded date. With 34,023 records, that formatter setup—not the 22.5 MB file read—was the dominant startup bottleneck. The viewport path then repeatedly filtered the statewide array, while each rendered SwiftUI marker added a 44 by 44 point button hit target over MapKit.

## Implemented path

- Reused a value-type ISO-8601 parse strategy instead of constructing formatters per date.
- Built one immutable spatial grid after the lazy catalog load.
- Cached exact viewport/plan results and per-plan parking-rule resolutions with bounded invalidation.
- Debounced settled camera changes by 250 ms, cancelled superseded work, and rejected stale generations.
- Preserved current marker arrays while a replacement refresh is in flight.
- Limited rendered annotations by zoom and truthfulness, retaining live/predicted and selected results before location-only warnings.
- Replaced marker `Button` hit targets with MapKit selection tags so annotations no longer tile the gesture surface.

## After

- The identical bundled-catalog measurement completed in 0.523–0.540 seconds (about 43 times faster).
- Eight moving real-catalog viewport queries completed in 0.392–0.414 seconds (about 24–28% faster), with 48 results per street view.
- A spatial-index correctness test confirms a street-scale query inspects only intersecting cells rather than all 34,023 records.
- Deterministic tests cover cache hits/invalidation, rapid viewport coalescing, cancellation, stale-result protection, and preservation of visible markers during refresh.
- A dense 160-location UI fixture renders no more than the zoom budget and performs a real XCUITest pinch followed immediately by a duration selection.

The decoder number is the largest practical improvement because it removes roughly 22.7 seconds from the first static-catalog load. Network latency from the City of Melbourne and MapKit remains external and variable; cancellation prevents an old response from replacing a newer viewport but cannot make those services respond faster.

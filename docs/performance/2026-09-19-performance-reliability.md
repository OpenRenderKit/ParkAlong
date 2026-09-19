# Performance and reliability evidence - 19 September 2026

All measurements below were run with Xcode 27.0 `27A266a` on an iPhone 17 Pro iOS 26.5 simulator with isolated DerivedData.

## Baseline regressions

The pre-fix pass exposed three reliability regressions in the current map and repository path:

- A canceled refresh still decoded the historical fallback, with `history_loads=1`.
- After 40 unique pans, the first viewport remained cached, with `requests=40`, showing an unbounded local viewport cache.
- A late zone 7001 vacant-bay response overwrote a newer zone 7002 selection.

## Fixes

- `ParkingRepository`: added `Task.checkCancellation()` after live fetch, before and after historical fallback load, and on empty-result and error paths, so cancellation never triggers the historical decode. Replaced the unbounded viewport cache with a bounded `cacheLimit` default of 16, with LRU recency on hits and eviction of the oldest entry. `CancellationError` is rethrown rather than converted to fallback data.
- `RemoteParkingClient` in `RemoteParkingRepository.swift`: added matching bounded cache behavior with a default limit of 16, LRU recency on hits, and recency refresh on HTTP 304 ETag revalidation. Added cancellation checks before network work, after response, before decode, and after validation, with no cache write on cancellation.
- `ParkingAPIClient`: added `Task.checkCancellation()` after page fetch and before pagination continues, so canceling stops further page work. Covered by a focused pagination cancellation test asserting one request and `CancellationError`.
- `ParkingMapViewModel`: added vacant-bay request generation tracking. Each `selectZone` starts a new generation, clears prior bays, and only applies the result when generation and selected zone still match. Pending vacant-bay work is invalidated on refresh, destination change, off-street selection, static cluster selection, zone dismissal, and when a refresh drops the selected zone from the viewport. A stale late response for zone 7001 is therefore rejected after zone 7002 is selected.
- `DestinationSearchService`: added cancellation checks across MapKit completion and search steps and guarded completion callbacks by request ID, so a superseded completer cannot overwrite newer results.
- `StaticParkingRepository`: rewrote static text search as a cancellable loop with early empty returns on `Task.isCancelled`, preserving the existing scoring and limit behavior.
- Offline and empty behavior is preserved: live failure and empty live results still fall back to historical typicals, remote failure still falls back to bundled parking, oversized or incompatible remote payloads are still rejected, and no product UI change was retained.

## After evidence

Focused repository and remote tests confirm the fixes:

- Canceled refresh: `canceled_refresh_seconds=0.000071833` with `history_loads=0`.
- Real bundled historical decode: `0.789801166` seconds for `225792` records, showing the avoided work when cancellation skips the fallback.
- Bounded local cache: after 40 unique viewports plus a repeat of the first viewport, `requests=41`, confirming the oldest entry is re-fetched instead of retained indefinitely. Default limit is 16. A separate recency test confirms a cache hit keeps that viewport newer than an unvisited one.
- Vacant-bay selection: the newer zone 7002 result is retained and the late zone 7001 response is rejected; a refresh that removes the selected zone clears selection and bays.
- Remote cache: the default limit of 16 with LRU eviction and ETag recency are covered, including 304 revalidation refreshing recency without adding an `If-None-Match` header on a truly evicted query.
- API pagination and MapKit/static search cancellation are guarded as described above.

Static catalog guardrails remain within limits:

- Bundled catalog decode: `0.380768208` seconds.
- Eight street queries: `0.254889375` seconds, 48 results each.

## UI guardrails

An experimental UI refactor was measured on the identical dense-map simulator workload and then reverted because it did not improve the guardrails. No product UI change was retained.

| Run | Launch | Pinch clock / CPU / peak memory | Selection workflow clock / CPU |
|---|---|---|---|
| Baseline original UI | 5.059s | 2.018s / 0.630s / 195.8MB | 3.721s / 0.503s |
| Experimental UI refactor | 5.146s | 1.983s / 0.633s / 210.8MB | 3.781s / 0.510s |
| Final original UI | 5.162s | 2.012s / 0.635s / 194.5MB | 3.783s / 0.535s |

The final original UI run passed all four focused UI cases. The captured selection metric covers tap, detail sheet appearance, swipe dismissal, and the surrounding measured workflow, including a 1s negative wait in that run, so it is a workflow guardrail, not pure tap latency. The committed UI guardrail replaces that fixed negative wait with an event-driven disappearance predicate and prints a separate three-sample tap-to-sheet latency summary.

The final full-suite run measured launch-to-marker readiness at `5.158s` mean and dense pinch at `2.011s` clock, `0.659s` app CPU, and `203.7MB` mean peak physical memory. XCUI-observed tap-to-detail samples, including element-query polling overhead, were `1.548s`, `1.621s`, and `1.793s`, for a `1.654s` mean. The broader selection and dismissal workflow used `0.690s` mean app CPU and `148.7MB` mean peak physical memory. These are simulator guardrails, not physical-device service-level targets.

## Live smoke and test scope

- Final live smoke: `1.189s`, `1485` spatial rows, `781` trusted, newest `2026-09-19T02:37:53Z`.
- Focused API tests: `4/4` passed.
- Remote tests: `10/10` passed.
- Python generator tests: `27/27` passed in `0.403s`.
- Final isolated Xcode run: `160/160` passed, comprising `133` unit tests and `27` UI tests with no skips or runtime warnings. The Xcode test operation completed in `295.447s`.
- Final unit performance recheck: historical decode `0.896222458s` for `225792` records, canceled refresh `0.000114917s` with `history_loads=0`, bounded cache request count `41`, bundled catalog decode `0.385654458s`, and eight street queries `0.287582625s` with 48 results each.

Simulator timing and City of Melbourne plus MapKit latency remain external and variable. Cancellation and generation guards prevent an old response from replacing newer state but cannot make those services respond faster.

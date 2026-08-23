# ParkAlong Victoria-wide map, search, pricing, and prediction design

## Goal

Make ParkAlong a Victoria-wide, map-first parking product that reacts to the visible map, resolves legal stays and prices for a chosen arrival time, presents calibrated forecasts as a first-class experience, and uses native iOS 26/27 presentation where available while preserving a complete iOS 17–25 path.

## Approved scope

The implementation covers the ten user-reported issues and the subsequent statewide research direction:

1. replace individual duration pills and the cramped More menu with a coherent sliding duration dock and an Arrival & Stay planner;
2. repair destination/search positioning and rebuild search around native completion, parking-aware ranking, and useful states;
3. substantially expand current price coverage with effective-dated rate tables and clearly labelled estimates;
4. rank both ordinary destinations and ParkAlong parking results, without a Melbourne-only search region;
5. center the About legend horizontally and vertically;
6. let upward content scrolling expand a partially presented detail/About sheet;
7. make time limits interactive and show schedules across hours and days;
8. remove the fake confidence percentage and replace it with measured probability/ranges or honest abstention;
9. ingest more OSM restriction/price tags and the useful council/contractor services found in the statewide audit;
10. calculate and render results from the visible map viewport, updating smoothly after pan/zoom.

The implementation also establishes a hybrid data boundary: a bundled Victoria seed remains usable offline, while a versioned remote endpoint can supply viewport-scoped updates, price/rule corrections, model metadata, and signed/hashed dataset versions. The app must still work when that endpoint is unavailable.

## Source truth and adapter architecture

There is no universal council parking format. Every source adapter maps its input into a shared normalized record while retaining source identity and evidence type.

Supported evidence types remain distinct:

- fresh direct occupancy;
- historical occupancy;
- static authority geometry/rules/prices;
- public contractor-hosted geometry;
- consumer app or partner-only claims;
- OpenStreetMap community data;
- demand context without occupancy labels.

The public Colac Otway, Monash, and Southern Grampians ArcGIS services are approved for inclusion. Their records are searchable and visible, with the actual publisher/host attribution retained. Their provenance label must not prevent normal use, but it must not be rewritten as a direct council publication.

Every normalized location has a stable ID, geometry, source attribution, evidence classification, optional capacity/accessibility, schedules, tariffs, archetype, dataset time, checked time, and optional prediction evidence.

## Hybrid data delivery

### Bundled seed

The generated Victoria catalogue remains the offline baseline. It is deterministic, attributed, filtered for explicitly restricted OSM access, and accompanied by a manifest containing source counts, generation time, content version, and hashes.

### Remote viewport endpoint

The app can request an environment-configured endpoint using:

`GET /v1/parking?west=&south=&east=&north=&arrival=&durationMinutes=&zoom=&catalogVersion=`

The response contains normalized locations/options, data/model version, generated time, cache TTL, and optional next cursor. HTTP ETag/If-None-Match is supported. Remote data may correct or replace an older bundled record by stable ID; it may never demote a fresher verified occupancy event to an older value.

The initial repository ships with the endpoint disabled unless a base URL is configured. Network unavailability, invalid JSON, incompatible versions, or failed validation fall back to the bundled seed without clearing currently visible pins.

### Cache and viewport behavior

Map camera changes are observed continuously for visual state but trigger data refresh only after interaction ends. The requested rectangle is the visible map rectangle expanded by roughly 20 percent to avoid edge churn. Cache keys include spatial tile/rectangle, arrival bucket, stay duration, catalogue version, and model version.

Results are recomputed when:

- the final visible rectangle materially changes;
- zoom crosses a clustering/detail threshold;
- arrival date/time or duration changes;
- the user explicitly refreshes;
- a relevant cached response expires.

Existing pins remain visible during an update. Results outside the current viewport are removed only after a valid replacement result is ready. Wide zooms cluster; closer zooms reveal individual locations or street zones.

## Arrival and stay controls

The bottom control is one horizontally coherent glass/material dock, not unrelated circular buttons.

The primary slider/segmented track exposes:

`15m · 1h · 2h · 3h · 4h · 6h · 8h+`

It supports tap and drag selection, has a visible moving selection indicator, provides selection haptics, exposes an adjustable accessibility action, and does not rely on color alone. The refresh action remains adjacent but visually separate from the duration track.

`8h+` and the planner action open an Arrival & Stay sheet with:

- Today / Tomorrow / date picker;
- arrival time rounded to a sensible interval but manually editable;
- duration presets plus a custom duration;
- an explicit overnight/day-boundary summary;
- Apply and Reset actions.

Changing the plan reruns legality, pricing, forecasting, viewport results, and ranking for the selected arrival—not merely for the current clock time.

## Search experience

Search uses `MKLocalSearchCompleter` for responsive completions and `MKLocalSearch` for resolved places. It is biased to the current visible region, not hard-coded to a 12 km Melbourne rectangle.

The search sheet places a native search field at the top and preserves results while new completions load. It shows:

- completion and destination matches;
- ParkAlong parking facilities/streets near the query or visible map;
- current location and search-this-area actions;
- recent in-session queries only when useful (no account or persistent profiling);
- explicit loading, no-result, offline, and failure states.

Ranking combines text relevance, distance to the requested destination/viewport, whether the result is a parking facility, legal fit for the chosen stay, source quality, price knowledge, and—only where supported—availability probability. It does not blindly take the first six MapKit results.

Selecting a destination updates the map camera first, then queries the resulting viewport once. Selecting a parking result selects its pin and opens detail without replacing the destination incorrectly.

## Rules, time limits, and prices

`ParkingRuleResolver` remains the authority for active legality. It is extended to resolve an explicit arrival date/time and arbitrary duration, public holidays, overnight windows, multiple daily schedules, exceptions, effective dates, and stepped tariffs.

The detail sheet's Time Limit row is a button. It opens a schedule explorer showing:

- the active rule at the planned arrival;
- legality for the requested stay;
- a seven-day strip and the selected day's chronological rule blocks;
- free/unrestricted periods, paid periods, limits, permit/loading/accessibility exceptions, and unknown gaps;
- posted-sign precedence and source/effective date.

Pricing uses a versioned rate ledger. Deterministic authority rates calculate the total for the selected arrival/stay. Recent operator quotes may show a range and timestamp. Unknown prices remain unknown. A council-wide average is never assigned to an individual facility.

OSM ingestion reads `fee`, `charge`, `maxstay`, `opening_hours`, `access`, parking subtype, capacity, and supported conditional forms. Unparseable conditions are retained as source text and fail closed for legality/price rather than being ignored.

## Prediction product contract

The generic “confidence %” is removed.

### Ground truth rebuild

Historical generation creates an explicit observation grid that distinguishes occupied, vacant, offline/not observed, bay not installed, restriction inactive, and unknown. Missing intervals are never replaced silently by the nearest occupied interval. Multi-year Melbourne data is supported by the generator; COVID-affected periods and material rule/geometry changes are tagged.

### Model ladder

The first shippable model is an interpretable hierarchical seasonal baseline with live correction. More complex tabular or graph models are admitted only when rolling and geographic holdouts beat that baseline.

Prediction output contains:

- expected available count when capacity is known;
- lower/upper calibrated interval;
- probability of at least one legal space;
- forecast horizon and model version;
- evidence tier and observed-through date;
- calibration metrics used for release eligibility.

Validation uses rolling-origin and geographic holdouts, count MAE/pinball loss, probability Brier score/reliability, and empirical interval coverage. Models abstain when source health, rule coverage, capacity, support, calibration, or distribution-shift gates fail.

### User-facing states

- **Live now:** fresh observed count and event age.
- **Live-informed forecast:** calibrated range/probability for arrival.
- **Historical forecast:** calibrated typical range with observation period.
- **Demand outlook:** qualitative busy/moderate/quieter signal without a fabricated vacancy count.
- **Location/rules only:** availability unknown.

Source quality and prediction uncertainty are separate concepts. Neither is shown as an unexplained universal percentage.

## Map, detail, and About presentation

The map remains full-screen. The destination control is a well-positioned toolbar/search target rather than a loose centered magnifier. Current-location and overflow actions retain 44-point hit targets.

The detail sheet starts at an appropriate compact/medium detent. Content scrolling uses sheet-resize interaction so an upward gesture at the top expands the sheet before scrolling deeply. The Navigate action remains reachable through a safe-area inset.

The About legend uses equal-width cells with centered badge/icon and text alignment on both axes. It remains readable at Dynamic Type accessibility sizes and can reflow without clipping.

## iOS 26/27 and compatibility

The deployment target remains iOS 17.

- iOS 26+ uses native Liquid Glass for functional floating controls, interactive selection, toolbar actions, and the primary Navigate action.
- iOS 27-only toolbar priority, pinned action, overflow, minimization, status-bar, and resizable-window refinements are isolated behind compiler and runtime availability gates.
- iOS 17–25 uses equivalent SwiftUI material/system-button fallbacks.
- Reduce Transparency selects an opaque high-contrast surface.
- Reduce Motion removes morph/scale transitions without removing state feedback.
- information cards and legal/source content remain solid/material rather than decorative glass.

No third-party UI dependency is introduced.

## Reliability and testing

Implementation is test-first where behavior is deterministic:

- source adapter fixtures, attribution, normalization, and deduplication;
- OSM schedule/price parsing;
- arbitrary arrival/duration, weekdays, public holidays, overnight and effective-date rules;
- price totals and caps;
- explicit historical empty/offline buckets and no-nearest-bucket regression;
- probability/calibration/abstention behavior;
- viewport rectangle changes, cache keys, stale-result preservation and clustering;
- search completion/result ranking and cancellation;
- accessibility semantics for the duration control, pins, time-limit row, forecast states and Navigate action;
- UI flows for search, duration planning, map pan/zoom, sheet expansion, schedule explorer and navigation.

Verification includes XcodeGen, all Python tests, Swift unit/UI tests, builds with the installed stable and beta toolchains where available, `compileall`, `git diff --check`, and visual inspection in light/dark, large Dynamic Type, Reduce Motion and Reduce Transparency.

## Delivery constraints

- Preserve the ParkAlong name and bundle identifier.
- Preserve truthful live/static/historical/prediction classification.
- Do not require an account for public parking discovery.
- Do not store API keys in source control.
- Do not claim an unconfigured remote endpoint is deployed.
- Do not claim numeric statewide vacancy where the model abstains.
- Posted signs and facility notices remain authoritative.

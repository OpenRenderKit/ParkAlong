# Victoria Static Parking and Predictions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand ParkAlong across Victoria with trustworthy static parking locations, current time and price rules where verified, calibrated non-live predictions, and a simple map language that never presents static or stale data as live.

**Architecture:** Keep City of Melbourne as the only runtime live-occupancy adapter. Generate a compact, attributed static catalog from anonymous public council endpoints and curated official rules, merge it with live results at runtime, and resolve restrictions and tariffs for the user's requested stay in Australia/Melbourne time. Predictions are gated by evidence quality and calibration metadata; unsupported locations remain red `P` location-only results.

**Tech Stack:** Swift 6, SwiftUI, MapKit, Foundation Codable, XCTest/XCUITest, Python 3 standard library, XcodeGen, anonymous council ArcGIS/Opendatasoft/JSON endpoints.

**Spec:** `docs/victoria-parking-data-sources.md`

## Global Constraints

- The product name remains exactly `ParkAlong`.
- A result is live only with a recognized occupied/vacant state, usable location, and fresh source event timestamp.
- Static, historical, predicted, and live timestamps/classifications remain separate.
- No account, session, private token, credential, or commercial partnership API is used.
- Street signs and facility notices remain authoritative.
- Predicted pins use flat deep plum `#6B3A6E`, a leading `~`, and a small amber warning.
- Location-only pins use a flat red `P` and a small amber warning.
- UI implementation is performed through Cursor CLI model `cursor-grok-4.6-high`, not Cursor Subagents.

---

### Task 1: Source-aware parking domain and current rule resolution

**Files:**
- Create: `ParkAlong/Domain/ParkingSource.swift`
- Create: `ParkAlong/Domain/ParkingRuleResolver.swift`
- Modify: `ParkAlong/Domain/ParkingModels.swift`
- Modify: `ParkAlong/Domain/ParkingOption.swift`
- Test: `ParkAlongTests/ParkingRuleResolverTests.swift`

**Interfaces:**
- Produces: `ParkingDataClassification`, `ParkingSourceAttribution`, `StaticParkingLocation`, `ParkingSchedule`, `ParkingTariff`, `ResolvedParkingRule`, and `ParkingRuleResolver.resolve(location:at:duration:)`.
- `ParkingOption` exposes classification, warning text, source timestamps, active restriction, and resolved price without deriving live state from `checkedAt`.

- [ ] Write tests proving weekday/public-holiday schedule selection, overnight ranges, stepped facility tariffs, first-hour-free pricing, expired tariff rejection, and ambiguous-rule fail-closed behavior.
- [ ] Run the focused tests and confirm they fail because the new types/resolver do not exist.
- [ ] Add source/classification models and a deterministic Melbourne-time rule resolver.
- [ ] Run the focused tests and all existing domain tests.

### Task 2: Anonymous Victorian static-catalog generator

**Files:**
- Create: `Scripts/generate_victoria_static_catalog.py`
- Create: `Scripts/tests/test_generate_victoria_static_catalog.py`
- Create: `ParkAlong/Resources/Generated/victoria_static_parking.json`
- Modify: `ParkAlong/Resources/Generated/README.md`

**Interfaces:**
- Consumes anonymous public endpoints only.
- Produces an array of `StaticParkingLocation` JSON records with stable IDs, council/source attribution, geometry, capacity, accessibility, schedules, tariffs, archetype, dataset timestamp, checked timestamp, and prediction evidence.

- [ ] Write fixture-driven tests for ArcGIS polygon centroids, Opendatasoft point/polygon extraction, Boroondara JSON cleanup, source attribution, stable deduplication, and exclusion of unusable geometry.
- [ ] Run the Python tests and confirm the generator tests fail before implementation.
- [ ] Implement adapters for Maribyrnong, Ballarat, Casey, and Boroondara plus curated official tariff/location records for Stonnington, Shepparton, Frankston, Bendigo, Werribee, and Whitehorse.
- [ ] Generate the bundled catalog from current anonymous sources; network failures must fail the generation instead of silently shipping an empty council.
- [ ] Run generator tests, JSON decode checks, and record/source count validation.

### Task 3: Runtime static repository and source-aware merge

**Files:**
- Create: `ParkAlong/Data/StaticParkingRepository.swift`
- Modify: `ParkAlong/Data/BundleDataLoader.swift`
- Modify: `ParkAlong/Data/ParkingRepository.swift`
- Modify: `ParkAlong/App/AppEnvironment.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Test: `ParkAlongTests/StaticParkingRepositoryTests.swift`
- Test: `ParkAlongTests/ParkingRepositoryTests.swift`

**Interfaces:**
- Produces: `StaticParkingProviding.options(near:duration:at:)` and a combined `ParkingRepositoryResult.options` ordered live, predicted, then location-only.
- Runtime never contacts static council endpoints; the checked and dataset timestamps come from the bundled artifact.

- [ ] Write tests for distance filtering, dense-bay clustering, requested-stay eligibility, source classification preservation, and live/static merge ordering.
- [ ] Run the focused tests and confirm expected failures.
- [ ] Implement bundled loading, clustering and combined result wiring.
- [ ] Run repository and view-model tests.

### Task 4: Calibrated prediction eligibility and demand features

**Files:**
- Modify: `ParkAlong/Domain/PredictionEngine.swift`
- Modify: `ParkAlong/Domain/ParkingModels.swift`
- Modify: `Scripts/generate_prediction.py`
- Modify: `Scripts/tests/test_generate_prediction.py`
- Test: `ParkAlongTests/PredictionRankingCacheTests.swift`

**Interfaces:**
- Produces: `PredictionEvidence`, `ParkingDemandContext`, and `PredictionEngine.staticEstimate(...) -> AvailabilityPrediction?`.
- A static estimate requires known capacity, a supported parking archetype, sufficient labelled samples, and acceptable calibration error; otherwise it returns `nil` and the UI shows a red `P`.

- [ ] Write failing tests for minimum sample gates, calibration-error gates, price/restriction demand adjustments, seasonal beach demand, and confidence bounds.
- [ ] Extend generated historical buckets with validation metadata and archetype-compatible features without loading raw archives in the app.
- [ ] Implement the gated hierarchical estimate and preserve the existing live-plus-history calculation.
- [ ] Run prediction generator and Swift prediction tests.

### Task 5: Simple, accessible map and detail UX through Cursor CLI

**Files:**
- Modify through Cursor CLI: `ParkAlong/Features/Map/AvailabilityPin.swift`
- Modify through Cursor CLI: `ParkAlong/Features/Map/ParkingMapView.swift`
- Modify through Cursor CLI: `ParkAlong/Features/Map/MapControls.swift`
- Modify through Cursor CLI: `ParkAlong/Features/ZoneDetail/ZoneDetailView.swift`
- Modify through Cursor CLI: `ParkAlongUITests/ParkAlongUITests.swift`
- Test: `ParkAlongTests/ParkingOptionTests.swift`

**Interfaces:**
- Consumes source-aware `ParkingOption` values.
- Produces three unambiguous presentations: fresh live number, plum `~N` plus amber warning, and red `P` plus amber warning.

- [ ] Add model-level assertions for accessibility labels and display semantics, then run them to verify failure.
- [ ] Invoke `cursor-agent -p --force --model cursor-grok-4.6-high --workspace /Users/sid/.codex/worktrees/16ab/ParkAlong` with the approved visual and accessibility specification.
- [ ] Independently review Cursor's diff for data-truth violations, clutter, Dynamic Type, contrast, VoiceOver, reduced motion, and 44-point targets; patch non-UI wiring outside Cursor if needed.
- [ ] Run focused unit tests and XCUITests, inspect light/dark simulator screenshots, and iterate through the same Cursor CLI model for UI-only corrections.

### Task 6: Documentation and release verification

**Files:**
- Modify: `README.md`
- Modify: `docs/victoria-parking-data-sources.md`
- Modify: `ParkAlong/Resources/Generated/README.md`

**Interfaces:**
- Documents exact bundled counts, source classifications, checked/effective dates, ODbL/CC BY attribution, UI legend, prediction limits, and regeneration commands.

- [ ] Update documentation from the generated manifest and verified app behavior.
- [ ] Regenerate the Xcode project with `xcodegen generate`.
- [ ] Run all Python tests, Swift unit tests, XCUITests, `python3 -m compileall -q Scripts`, and `git diff --check`.
- [ ] Report exact test counts, source counts, timestamps, screenshots, and remaining limitations without calling any unverified feed live.

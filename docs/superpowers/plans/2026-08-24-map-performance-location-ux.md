# ParkAlong Map Performance, Location, and UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make statewide parking discovery fast, cancellable, location-first, visually truthful, and thoroughly testable without weakening the distinction between live, predicted, static, and unknown data.

**Architecture:** Decode and index the bundled catalog once outside the main actor, query only spatial cells intersecting the padded viewport, and cache bounded query results. Let the main-actor view model own debounce/cancellation/generation state while pure marker and startup-location policies remain independently testable. Keep SwiftUI presentation adaptive: native iOS 26/27 Liquid Glass where available and material/opaque iOS 17 fallbacks.

**Tech Stack:** Swift 6, SwiftUI, MapKit, Core Location, Observation, OSLog signposts, XCTest/XCUITest, XcodeGen, Python unittest.

**Spec:** User delegation dated 2026-08-24 in Codex task `01a02e04-207d-7c21-b357-45bf4dcb37d0`.

## Global Constraints

- Work directly in `/Users/sid/Documents/Coding/ParkAlong` on the focused `codex/map-performance-location-ux` branch.
- Preserve ParkAlong branding and iOS 17 deployment support.
- Use `project.yml` as the XcodeGen source of truth.
- Use `Australia/Melbourne` for parking-rule and arrival-time behavior.
- Never present static, stale, or uncertain data as live or green availability.
- Delegate a focused SwiftUI duration-control pass to Cursor CLI model `cursor-grok-4.6-high`; Codex reviews and owns integration.
- Do not merge or push `main`.

---

### Task 1: Capture baseline evidence and executable regressions

**Files:**
- Modify: `ParkAlongTests/StaticParkingRepositoryTests.swift`
- Modify: `ParkAlongTests/ParkingMapViewModelTests.swift`
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`

**Interfaces:**
- Consumes: current `StaticParkingProviding`, `ParkingRepositoryProviding`, and `LocationProviding` contracts.
- Produces: deterministic failures for repeated full scans, stale viewport replacement, startup location, denied fallback, and duration selection.

- [ ] Add a real-catalog XCTest that reports initial decode/index/query timing and repeated Melbourne/suburban/statewide query timings.
- [ ] Add controllable actor fakes whose continuations expose when a viewport request starts, cancels, and finishes; assert the newest request alone becomes visible.
- [ ] Add startup UI seams for authorized, denied, timeout, and unavailable location outcomes without sleeps.
- [ ] Run each new test against the baseline and record the expected failure or timing.

### Task 2: Build the immutable statewide spatial catalog

**Files:**
- Create: `ParkAlong/Data/StaticParkingSpatialIndex.swift`
- Modify: `ParkAlong/Data/StaticParkingRepository.swift`
- Modify: `ParkAlong/Data/BundleDataLoader.swift`
- Create: `ParkAlong/Support/ParkingPerformance.swift`
- Modify: `ParkAlongTests/StaticParkingRepositoryTests.swift`

**Interfaces:**
- Produces: `StaticParkingSpatialIndex.init(locations:)`, `locations(in:)`, catalog metrics, pre-normalized search text, and bounded query-cache keys.
- Consumes: `StaticParkingLocation`, `ParkingViewport`, and the existing Melbourne-time rule resolver.

- [ ] Write failing index-correctness tests comparing indexed results with a hand-derived fixture set, including cell edges and viewport padding.
- [ ] Write a failing cache test proving an equivalent viewport/plan query does not rerun catalog selection.
- [ ] Implement one-time detached decode/index construction and OSLog signposts for decode, index build, spatial lookup, rule resolution, and total static query.
- [ ] Replace per-viewport full-catalog scanning and repeated search normalization with indexed candidates and normalized catalog entries.
- [ ] Add bounded result caching and cancellation checks between expensive stages.
- [ ] Verify exact result correctness and capture real-catalog before/after timings.

### Task 3: Make viewport loading cancellable and state-preserving

**Files:**
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapView.swift`
- Modify: `ParkAlongTests/ParkingMapViewModelTests.swift`

**Interfaces:**
- Produces: one owned debounced viewport task, one owned active refresh task, generation-safe application, and stable visible arrays while loading.
- Consumes: repository/off-street/static async services and `ParkingViewport.materiallyDiffers(from:)`.

- [ ] Write failing tests for debounce coalescing, in-flight cancellation, stale completion rejection, preserved pins during refresh, and no refresh for immaterial camera jitter.
- [ ] Refactor refresh scheduling so a newer viewport cancels debounce and in-flight work before starting a 250 ms settled query.
- [ ] Keep the last successful visible markers during loading and apply all three result families atomically for the current generation.
- [ ] Add OSLog signposts containing generation, viewport, candidate count, visible count, cache hit, and elapsed time.
- [ ] Verify rapid pan/zoom tests without arbitrary sleeps.

### Task 4: Implement location-first startup as a finite state machine

**Files:**
- Modify: `ParkAlong/Services/LocationService.swift`
- Modify: `ParkAlong/App/AppEnvironment.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapView.swift`
- Modify: `ParkAlongTests/ParkingMapViewModelTests.swift`
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`

**Interfaces:**
- Produces: `LocationRequestResult` with success, denied, restricted, timed-out, and unavailable cases; one-shot startup centering and explicit fallback notices.
- Consumes: Core Location authorization callbacks and deterministic fixture launch arguments.

- [ ] Write failing unit tests proving authorized startup centers once before querying, first-run completion centers once, denial falls back, timeout finishes, and later map gestures are never snapped back.
- [ ] Replace the optional-coordinate continuation with a single-resume state machine and bounded timeout/cancellation cleanup.
- [ ] Start location acquisition on launch, refresh around the usable fix, and use Melbourne CBD only after an explicit non-success outcome.
- [ ] Add fixture seams and XCUITests for authorized current location, denied fallback, timeout, and unavailable simulation.

### Task 5: Establish truthful density-aware marker hierarchy

**Files:**
- Create: `ParkAlong/Features/Map/ParkingMarkerSelector.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapView.swift`
- Modify: `ParkAlong/Features/Map/AvailabilityPin.swift`
- Modify: `ParkAlong/Features/Map/MapControls.swift`
- Create: `ParkAlongTests/ParkingMarkerSelectorTests.swift`
- Modify: `ParkAlongTests/ParkingOptionTests.swift`

**Interfaces:**
- Produces: pure density budgets and stable selection that ranks selected, verified-live, predicted, official static, and generic location-only data in that order while preserving truthful palettes; MapKit-native tagged selection instead of a screen-covering layer of SwiftUI marker buttons.
- Consumes: live zones, static/off-street options, selected option, viewport zoom, and cell occupancy.

- [ ] Write failing suburban/CBD fixture tests for marker budgets, useful-result priority, stable selection, selected-marker retention, and deterministic density filtering.
- [ ] Implement a grid-aware selector that limits low-value warnings more aggressively when useful live/predicted markers are present.
- [ ] Replace overlapping 44-point annotation `Button` hit targets with MapKit selection tags so pinch and pan gestures retain native multi-touch ownership even in dense areas.
- [ ] Keep live green/orange/red and predicted plum semantics; make location-only markers smaller and visually muted without making them green.
- [ ] Update the legend and accessibility labels to match the truthful hierarchy.

### Task 6: Replace the stay control with a native adaptive segmented switcher

**Files:**
- Modify: `ParkAlong/Features/Map/MapControls.swift`
- Modify: `ParkAlong/DesignSystem/AdaptiveChrome.swift`
- Modify: `ParkAlongTests/AdaptiveChromeTests.swift`
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`

**Interfaces:**
- Produces: horizontally usable native-style selections for `15m`, `1h`, `2h`, `3h`, `4h`, `6h`, and `8h+`, retaining the custom planner.
- Consumes: `ParkingPlan`, `StayDuration`, Dynamic Type, Reduce Motion, Reduce Transparency, and iOS availability.

- [ ] Run Cursor CLI in the saved checkout with `--model cursor-grok-4.6-high --yolo` and restrict its ownership to the visual duration-control presentation.
- [ ] Review Cursor's diff for native semantics, 44-point targets, horizontal scrolling, Dynamic Type, and graceful iOS 17 material fallback.
- [ ] Integrate/fix presentation while retaining Codex-owned selection wiring and tests.
- [ ] Run duration XCUITests at normal and accessibility text sizes.

### Task 7: Regenerate, verify, visually inspect, and commit

**Files:**
- Modify: `project.yml` only if new paths require explicit project configuration.
- Regenerate: `ParkAlong.xcodeproj/project.pbxproj` when project structure changes.

- [ ] Run `/opt/homebrew/bin/xcodegen generate --spec project.yml` after structural changes.
- [ ] Run Python generator/source tests and compileall if the data pipeline changes.
- [ ] Run all relevant Swift unit tests, full XCUITests, and a clean simulator build on available iOS 26.x runtimes.
- [ ] Interactively run core flows in light/dark appearance and at one accessibility text size; capture screenshots and performance/signpost evidence.
- [ ] Run `git diff --check`, inspect the complete diff, confirm the branch is not `main`, and commit the verified implementation.

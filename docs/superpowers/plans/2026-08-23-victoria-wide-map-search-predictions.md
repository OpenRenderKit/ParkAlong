# ParkAlong Victoria-wide map, search, pricing, and predictions implementation plan

> Implement in the current `/Users/sid/Documents/Coding/ParkAlong` checkout. UI work must be performed through Cursor Agent CLI using `cursor-grok-4.6-high`, never a fast variant. Codex owns all non-UI implementation, wiring, review, and verification.

**Goal:** Deliver the approved Victoria-wide viewport-driven parking experience, useful search, arrival/day-aware rules and prices, calibrated prediction states, expanded public data coverage, and iOS 26/27-native UI with iOS 17 fallbacks.

**Spec:** `docs/superpowers/specs/2026-08-23-victoria-wide-map-search-predictions-design.md`

## Global constraints

- Keep `iOS: "17.0"`, ParkAlong naming, and the existing bundle identifier.
- Preserve current user changes and unrelated history.
- Write/extend failing tests before deterministic production behavior.
- Keep live, forecast, demand outlook, and location-only states separate.
- Include the approved Colac Otway, Monash, and Southern Grampians public layers with real host/publisher attribution.
- Never commit a credential or claim the optional remote API is deployed unless it actually is.
- Cursor may edit presentation files and UI tests only; Codex performs all data/domain/repository wiring and reviews every Cursor diff.

## Task 1: Lock the data and planning baseline

**Files:**
- Add/modify research, spec, plan, and generated-resource documentation only.

- [ ] Commit the statewide source checklist, prediction research, price research, source-audit update, approved design, and this plan.
- [ ] Record the exact `origin/main` base commit and branch.
- [ ] Run `git diff --check`.

## Task 2: Add the newly approved static source adapters

**Files:**
- Modify: `Scripts/generate_victoria_static_catalog.py`
- Modify: `Scripts/tests/test_generate_victoria_static_catalog.py`
- Regenerate: `ParkAlong/Resources/Generated/victoria_static_parking.json`
- Regenerate: `ParkAlong/Resources/Generated/victoria_static_manifest.json`

- [ ] Add fixture-first tests for Wodonga rules/capacity, Manningham car parks, Latrobe accessible spaces, Moorabool assets, and the approved Colac Otway/Monash/Southern Grampians public layers.
- [ ] Add stable IDs, explicit source classifications, attribution, geometry extraction, inactive/proposed filtering, and deduplication.
- [ ] Extend OSM normalization for capacity, accessibility, `fee`, `charge`, `maxstay`, `opening_hours`, and supported conditional tags.
- [ ] Regenerate the catalogue from current sources and verify per-source counts and manifest hashes.
- [ ] Run all generator tests, JSON decoding, `compileall`, and `git diff --check`.

## Task 3: Make arrival, duration, schedule, and pricing first-class domain concepts

**Files:**
- Modify: `ParkAlong/Domain/ParkingModels.swift`
- Modify: `ParkAlong/Domain/ParkingSource.swift`
- Modify: `ParkAlong/Domain/ParkingRuleResolver.swift`
- Modify: `ParkAlong/Domain/ParkingOption.swift`
- Modify: `ParkAlongTests/ParkingRuleResolverTests.swift`
- Modify: `ParkAlongTests/ParkingOptionTests.swift`

- [ ] Add failing tests for arbitrary/custom duration, future date/time, overnight windows, seven-day schedules, public holidays, effective dates, multiple daily restrictions, first-free-period pricing, stepped rates, daily caps, and unknown-condition fail-closed behavior.
- [ ] Introduce an immutable `ParkingPlan` containing arrival and duration.
- [ ] Resolve legality and price using `ParkingPlan`, not `Date.now` hidden inside views/repositories.
- [ ] Produce structured weekly schedule/detail rows for the schedule explorer.
- [ ] Preserve deterministic Australia/Melbourne formatting under a UTC test host.
- [ ] Run the focused domain tests and all existing domain tests.

## Task 4: Rebuild prediction truth, outputs, and release gates

**Files:**
- Modify: `Scripts/generate_prediction.py`
- Modify: `Scripts/tests/test_generate_prediction.py`
- Modify: `ParkAlong/Domain/PredictionEngine.swift`
- Modify: `ParkAlong/Domain/ParkingModels.swift`
- Modify: `ParkAlong/Data/ParkingRepository.swift`
- Modify: `ParkAlongTests/PredictionRankingCacheTests.swift`
- Modify: `ParkAlongTests/ParkingRepositoryTests.swift`

- [ ] Add failing generator tests proving explicit vacant, occupied, offline/unobserved, inactive, and unknown grid states; ensure empty intervals are not omitted.
- [ ] Add tests proving the runtime never substitutes an arbitrarily distant occupied bucket.
- [ ] Replace sample-count confidence with structured forecast probability, calibrated range, evidence tier, horizon, model version, Brier/calibration/coverage metadata, and abstention.
- [ ] Implement an interpretable hierarchical/seasonal baseline and live correction that can be evaluated deterministically from bundled model metadata.
- [ ] Keep demand-only sources qualitative unless validated occupancy labels exist.
- [ ] Add regression tests for no-data, low-support, poor-calibration, stale-model and out-of-distribution abstention.
- [ ] Regenerate the compact history/model artifact and report supported/abstaining coverage.

## Task 5: Add viewport-driven query, caching, and hybrid delta wiring

**Files:**
- Modify: `ParkAlong/Data/StaticParkingRepository.swift`
- Modify: `ParkAlong/Data/ParkingRepository.swift`
- Add: `ParkAlong/Data/RemoteParkingRepository.swift`
- Modify: `ParkAlong/App/AppEnvironment.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Modify/add focused repository and view-model tests.

- [ ] Add failing tests for bounding-box filtering, padding, zoom/detail thresholds, spatial/time/duration/model cache keys, ETag handling, remote override precedence, invalid remote response fallback, and preservation of visible results during refresh.
- [ ] Replace fixed 700 m/12 km assumptions with a normalized visible viewport request.
- [ ] Add the optional environment-configured remote endpoint client and bundled fallback; keep it disabled by default without configuration.
- [ ] Debounce/coalesce camera-end refreshes and prevent duplicate tasks.
- [ ] Cluster at wide zoom and reveal finer records at close zoom without silently changing data classification.
- [ ] Run repository/view-model tests including cancellation and stale-response ordering.

## Task 6: Rebuild search and parking-aware ranking wiring

**Files:**
- Modify: `ParkAlong/Services/DestinationSearchService.swift`
- Modify: `ParkAlong/Features/Map/ParkingMapViewModel.swift`
- Add/modify search tests.

- [ ] Add failing tests for completions, visible-region bias, statewide results, cancellation, stale-search suppression, parking-result merging, and relevance ranking.
- [ ] Implement `MKLocalSearchCompleter`-backed completion state and resolved MapKit search.
- [ ] Merge ParkAlong parking locations without allowing availability/source quality to overwhelm text relevance.
- [ ] Preserve previous results during loading and expose explicit loading/empty/error/offline states.
- [ ] Selecting a destination updates the camera then refreshes its viewport once; selecting parking opens detail.
- [ ] Run search and view-model tests.

## Task 7: Write UI interaction tests before the Cursor pass

**Files:**
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`
- Modify/add presentation-policy tests only where needed.

- [ ] Add initially failing UI coverage for the duration track, `8h+` planner, future-day plan, search field/results, visible-area refresh after pan/zoom, interactive time-limit row, weekly schedule explorer, sheet expansion, centered About legend semantics, and Navigate reachability.
- [ ] Preserve existing fixture and accessibility identifiers where they remain meaningful.
- [ ] Run the focused UI tests and capture the expected RED failures.

## Task 8: Implement all UI/UX through Cursor Grok 4.6 High

**Cursor-owned files:**
- `ParkAlong/Features/Map/ParkingMapView.swift`
- `ParkAlong/Features/Map/MapControls.swift`
- `ParkAlong/Features/Map/AvailabilityPin.swift`
- `ParkAlong/Features/Search/DestinationSearchView.swift`
- `ParkAlong/Features/ZoneDetail/ZoneDetailView.swift`
- presentation-only additions under `ParkAlong/DesignSystem/`
- `ParkAlongUITests/ParkAlongUITests.swift`

- [ ] Run Cursor from the current workspace:

```bash
cursor-agent -p --output-format stream-json --stream-partial-output \
  --workspace "$PWD" --model cursor-grok-4.6-high --trust --yolo \
  "Implement the UI/UX portions of docs/superpowers/specs/2026-08-23-victoria-wide-map-search-predictions-design.md and Task 8 of docs/superpowers/plans/2026-08-23-victoria-wide-map-search-predictions.md. You own SwiftUI presentation and UI tests only. Codex has implemented or will implement domain, data, repository, and view-model wiring. Build a premium native map-first experience: sliding 15m/1h/2h/3h/4h/6h/8h+ duration dock, Arrival & Stay planner with days/date/time/custom duration, correctly positioned search, native completion/result states, interactive weekly time-limit explorer, sheet scroll-to-expand behavior, centered About legend, viewport-loading feedback, honest live/forecast/outlook/unknown presentation, and reachable Navigate action. Use native iOS 26 Liquid Glass and useful iOS 27 APIs only behind compiler/runtime availability guards, with complete iOS 17-25 material/system fallbacks. Respect Reduce Motion, Reduce Transparency, Dynamic Type, VoiceOver, 44pt targets, and existing data classifications. Do not add business logic, third-party dependencies, credentials, hard-coded Melbourne regions, fake confidence, or unrelated changes. Run focused builds/tests where possible and return files changed, checks, blockers, assumptions, and a concise UX rationale."
```

- [ ] Review every Cursor diff for business-logic leakage, fixed screen sizing, availability mistakes, inaccessible targets, excessive glass, dropped identifiers, and lower-iOS compilation.
- [ ] Use a second bounded Cursor pass for visual/test corrections if required.
- [ ] Codex performs all wiring changes outside Cursor-owned presentation files.

## Task 9: Integrate, verify, and visually inspect

- [ ] Regenerate with `/opt/homebrew/bin/xcodegen generate --spec project.yml`.
- [ ] Run all Swift unit tests and all XCUITests on a dynamically available simulator.
- [ ] Run all Python tests and `python3 -m compileall -q Scripts`.
- [ ] Build with the stable toolchain and the installed iOS 27-capable/beta toolchain if present.
- [ ] Inspect light, dark, accessibility Dynamic Type, Reduce Motion, and Reduce Transparency states.
- [ ] Inspect main map, search, planner, schedule explorer, About legend, and detail sheet screenshots.
- [ ] Run `git diff --check` and inspect all changed files for secrets and source attribution.

## Task 10: Documentation and final delivery

- [ ] Update README screenshots/behavior, generated-resource documentation, source counts, regeneration commands, prediction states, pricing rules, viewport behavior, and optional remote configuration.
- [ ] Re-run the statewide source probe and record current classifications/timestamps.
- [ ] Commit focused changes with clear history.
- [ ] Report exact tests/builds, integrated source counts, model-supported versus abstaining coverage, remaining partner-only data, and any unavailable external deployment/device/CI verification.

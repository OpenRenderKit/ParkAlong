# ParkAlong Implementation Plan

> **For agentic workers:** Execute inline in this task. Subagent delegation is intentionally disabled; the standalone Cursor CLI is used only for the SwiftUI visual pass.

**Goal:** Deliver a runnable native iPhone app whose primary flow shows trustworthy live Melbourne on-street parking availability and navigates to a selected zone.

**Architecture:** Focused Swift types separate City API transport, repository/cache lifecycle, pure availability/restriction/prediction/ranking engines, platform services, view-model orchestration, and presentation. Deterministic fixtures exercise the complete UI while the normal launch path always uses live City data and bundled real historical/metadata artifacts.

**Tech Stack:** Swift 6, SwiftUI, MapKit, Core Location, URLSession, XCTest/XCUITest, Python 3 streaming preprocessing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-15-melbourne-parking-design.md`

## Global Constraints

- iOS only, minimum deployment target 17.0; simulator builds require no signing account.
- No auth, backend, reservation, payment, Google Maps, database, or runtime LLM calls.
- Live rows older than 24 hours are excluded; under-counting is preferred to false vacancy.
- Requested stay is a hard legal filter; unsupported or restricted signs are excluded.
- Normal app flow contains no fabricated availability.
- UI work must use standalone Cursor CLI with `cursor-grok-4.6-high`; review every diff locally.
- Raw 2019 data is ignored and never committed.

---

### Task 1: Project shell and contracts

Create XcodeGen configuration, app/test targets, Info.plist settings, focused folders, shared domain models, deterministic fixtures, and a compiling placeholder app shell. Generate `ParkingAvailability.xcodeproj` and establish a test-only dependency boundary.

### Task 2: Trustworthy live availability

Write failing decoder/request/pagination/freshness/grouping/cache tests. Implement `ParkingAPIClient`, `AvailabilityEngine`, expiring cache, and `ParkingRepository`; verify each red-green cycle and run a separate City API smoke request with measured freshness/count impact.

### Task 3: Restrictions, prediction, and ranking

Write failing table-driven tests for supported/unsupported restriction codes, weekday/weekend and midnight intervals, stay eligibility, live/history weighting and clamping, and availability-dominant ranking. Implement the pure engines. Add a streaming Python archive generator, a small generator fixture test, and bundled output derived from real 2019 source rows.

### Task 4: Platform services and orchestration

Implement Core Location, MapKit completion/search, Apple Maps handoff interception, refresh triggers, foreground/timer lifecycle, error/typical fallback states, and UI-test launch configuration. Keep the view model limited to orchestration and cover state transitions with deterministic tests.

### Task 5: SwiftUI visual implementation

Invoke `/Users/sid/.local/bin/agent --print --model cursor-grok-4.6-high` non-interactively with a precise native-iOS brief and explicit permission only for presentation files. Review the full diff, correct behavior/accessibility issues, build, screenshot, visually inspect, and invoke one additional refinement pass if any visual issue remains.

### Task 6: Simulator and end-to-end proof

Build for an available iPhone simulator, boot it, set `-37.8136,144.9631`, install/launch the live app, time visible results, and exercise destination, duration, zone detail, refresh, and intercepted navigation. Run the complete unit and UI suites. Capture main map, search, selected zone, loading/error, and light/dark screenshots and inspect each for clipping, contrast, hierarchy, and safe-area failures.

### Task 7: Delivery

Write the README with architecture, source attribution, setup/generation/test commands, caveats, privacy, and demo walkthrough. Verify ignored raw data, artifact sizes, clean project generation, final build/tests, and git status. Commit focused milestones only after their verification evidence is current.

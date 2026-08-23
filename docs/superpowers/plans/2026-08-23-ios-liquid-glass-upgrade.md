# ParkAlong iOS 26/27 Liquid Glass Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a faster map-to-navigation ParkAlong interface with native iOS 26 Liquid Glass, useful iOS 27 beta toolbar behavior, iOS 17–25 fallbacks, green CI, and verified installation on Sidhaarth’s iPhone 17 Pro.

**Architecture:** Keep `ParkingMapViewModel` and the repository layer unchanged as the state and data authorities. Add one presentation-only adaptive chrome boundary, reshape the existing SwiftUI map/search/detail views around standard navigation and glass controls, and compile iOS 27-only toolbar code behind both compiler and runtime availability gates.

**Tech Stack:** Swift 6, SwiftUI, MapKit, XCTest/XCUITest, XcodeGen, GitHub Actions, Python unittest, Cursor Agent CLI.

**Spec:** `docs/superpowers/specs/2026-08-23-ios-liquid-glass-upgrade-design.md`

## Global Constraints

- Preserve `iOS: "17.0"` in `project.yml`.
- Preserve the `ParkAlong` name and `com.sidkrishnan.ParkAlong` bundle identifier.
- Use iOS 26 Liquid Glass only through availability-gated SwiftUI code.
- Compile iOS 27-only source only with the Xcode 27 compiler and guard runtime use with `if #available(iOS 27, *)`.
- Keep live, predicted, and location-only data classifications truthful and visually distinct.
- Do not add comparison views, favourites, recent destinations, accounts, or persisted preferences.
- Do not add third-party UI dependencies.
- Use Cursor model `cursor-grok-4.6-high`; never use its `-fast` variant.

---

### Task 1: Make Melbourne schedule formatting independent of the host time zone

**Files:**
- Modify: `ParkAlongTests/ParkingRuleResolverTests.swift`
- Modify: `ParkAlong/Domain/ParkingRuleResolver.swift`

**Interfaces:**
- Consumes: `ParkingRuleResolver(timeZone:)` and `resolve(location:at:duration:)`.
- Produces: deterministic `ResolvedParkingRule.timeLimitText` and `restrictionWindow` strings using the resolver’s time zone.

- [ ] **Step 1: Add a regression test that forces the process default to UTC**

Add a test that saves `NSTimeZone.default`, sets it to UTC for the assertion, restores it with `defer`, resolves the existing weekday Melbourne fixture, and expects the hand-derived literals `2P until 5:30 pm` and `Active now · ends 5:30 pm`.

```swift
func testFormattingUsesResolverTimeZoneWhenHostDefaultsToUTC() {
    let previous = NSTimeZone.default
    NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
    defer { NSTimeZone.default = previous }

    let location = fixtureLocation(
        schedules: [
            .init(days: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 17 * 60 + 30,
                  maxStayMinutes: 120, restrictionText: "2P Meter", appliesOnPublicHolidays: false,
                  outsideWindowMeansUnrestricted: true)
        ],
        tariffs: []
    )

    let resolved = resolver.resolve(location: location, at: localDate("2026-08-20 10:15"), duration: .twoHours)

    XCTAssertEqual(resolved?.timeLimitText, "2P until 5:30 pm")
    XCTAssertEqual(resolved?.restrictionWindow, "Active now · ends 5:30 pm")
}
```

- [ ] **Step 2: Run only the regression and verify RED**

Run:

```bash
xcodebuild test -project ParkAlong.xcodeproj -scheme ParkAlong \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:ParkAlongTests/ParkingRuleResolverTests/testFormattingUsesResolverTimeZoneWhenHostDefaultsToUTC \
  CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL with a UTC-rendered end time rather than `5:30 pm`.

- [ ] **Step 3: Set the formatter boundary explicitly**

Replace the implicit `Date.FormatStyle` call in `formattedTime(minutes:)` with a `DateFormatter` whose calendar is Gregorian, locale is `en_AU`, time zone is `self.timeZone`, and date format is `h:mm a`. Normalize spaces and lowercase the result as before.

```swift
let formatter = DateFormatter()
formatter.calendar = Calendar(identifier: .gregorian)
formatter.locale = Locale(identifier: "en_AU")
formatter.timeZone = timeZone
formatter.dateFormat = "h:mm a"
return formatter.string(from: date)
    .replacingOccurrences(of: "\u{202F}", with: " ")
    .replacingOccurrences(of: "\u{00A0}", with: " ")
    .lowercased()
```

- [ ] **Step 4: Verify GREEN for the focused and affected suites**

Run the focused regression, then all `ParkingRuleResolverTests` and `StaticParkingRepositoryTests`. Expected: 16 tests, zero failures.

- [ ] **Step 5: Commit the root-cause fix**

```bash
git add ParkAlong/Domain/ParkingRuleResolver.swift ParkAlongTests/ParkingRuleResolverTests.swift
git commit -m "fix: make parking times timezone deterministic"
```

### Task 2: Add a tested adaptive chrome boundary

**Files:**
- Create: `ParkAlong/DesignSystem/AdaptiveChrome.swift`
- Create: `ParkAlongTests/AdaptiveChromeTests.swift`

**Interfaces:**
- Produces: `AdaptiveSurfaceKind`, `AdaptiveChromePolicy.surfaceKind(supportsLiquidGlass:reduceTransparency:)`, `AdaptiveGlassContainer`, `adaptiveGlassSurface(cornerRadius:)`, `adaptiveProminentAction()`, and iOS 27 navigation-chrome modifiers.
- Consumes: SwiftUI environment values for Reduce Transparency and Color Scheme.

- [ ] **Step 1: Write policy tests before the presentation implementation**

```swift
final class AdaptiveChromeTests: XCTestCase {
    func testLiquidGlassIsUsedWhenSupportedAndTransparencyIsAllowed() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(supportsLiquidGlass: true, reduceTransparency: false),
            .liquidGlass
        )
    }

    func testReduceTransparencyAlwaysUsesOpaqueSurface() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(supportsLiquidGlass: true, reduceTransparency: true),
            .opaque
        )
    }

    func testOlderSystemsUseMaterialSurface() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(supportsLiquidGlass: false, reduceTransparency: false),
            .material
        )
    }
}
```

- [ ] **Step 2: Run the policy tests and verify RED**

Expected: compilation failure because `AdaptiveChromePolicy` does not exist.

- [ ] **Step 3: Implement the minimal policy and adaptive SwiftUI helpers**

The modifier must select `.opaque` before checking OS availability. iOS 26 uses `.glassEffect(.regular.interactive(), in: RoundedRectangle(...))`; older systems use `.regularMaterial`. The prominent action uses `.glassProminent` on iOS 26+ and `.borderedProminent` before iOS 26.

Xcode 27-only references must be nested in `#if compiler(>=6.4)` and `if #available(iOS 27, *)`. Provide identity fallbacks in the `#else` path so Xcode 26 still compiles the file.

- [x] **Step 4: Verify GREEN under Xcode 26 and Xcode 27**

Run `AdaptiveChromeTests` with Xcode 26, then repeat using `DEVELOPER_DIR` pointing to the installed Xcode 27 beta. Expected: three tests pass in both toolchains.

- [ ] **Step 5: Commit the compatibility layer**

```bash
git add ParkAlong/DesignSystem/AdaptiveChrome.swift ParkAlongTests/AdaptiveChromeTests.swift
git commit -m "feat: add adaptive iOS chrome"
```

### Task 3: Redesign the map-first UI through Cursor Grok 4.6 High

**Files:**
- Modify: `ParkAlong/Features/Map/ParkingMapView.swift`
- Modify: `ParkAlong/Features/Map/MapControls.swift`
- Modify: `ParkAlong/Features/Map/AvailabilityPin.swift`
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`
- Modify: `ParkAlong/DesignSystem/AdaptiveChrome.swift`

**Interfaces:**
- Consumes: existing `ParkingMapViewModel`, accessibility identifiers, and adaptive chrome helpers from Task 2.
- Produces: native map toolbar, coherent bottom action layer, responsive annotations, and the unchanged destination/duration/selection actions.

- [ ] **Step 1: Add a failing fast-path UI test**

Launch the deterministic live fixture and assert that `destination-search-button`, `current-location-button`, `best-bet-button`, and `parking-action-dock` are all hittable before any sheet is presented. Tap `best-bet-button` and assert `zone-detail-sheet` appears.

- [ ] **Step 2: Run the new UI test and verify RED**

Expected: FAIL because `current-location-button` and `parking-action-dock` do not yet exist.

- [ ] **Step 3: Run Cursor in the current workspace with the exact requested model**

Use:

```bash
cursor-agent -p --output-format stream-json --stream-partial-output \
  --workspace "$PWD" --model cursor-grok-4.6-high --trust --yolo \
  "You are a Cursor UI subagent working for Codex. Implement Task 3 from docs/superpowers/plans/2026-08-23-ios-liquid-glass-upgrade.md and follow docs/superpowers/specs/2026-08-23-ios-liquid-glass-upgrade-design.md. Work in the current workspace. Do not revert unrelated changes. Preserve iOS 17, all existing accessibility identifiers, data truthfulness, and business logic. Use the adaptive chrome layer. Keep Liquid Glass to functional controls. Run the focused UI test. Return summary, files changed, checks run, blockers, and assumptions."
```

- [ ] **Step 4: Review Cursor’s diff before accepting it**

Reject any business logic moved into views, duplicate availability branches outside the adaptive layer, fixed screen widths, glass on information content, dropped identifiers, or unverified claims. Correct focused issues with `apply_patch`.

- [ ] **Step 5: Verify GREEN on the focused fast-path UI test and map unit tests**

Run the new UI test plus `ParkingMapViewModelTests` and `ParkingOptionTests`. Expected: all selected tests pass.

- [ ] **Step 6: Commit the map redesign**

```bash
git add ParkAlong/Features/Map ParkAlong/DesignSystem/AdaptiveChrome.swift ParkAlongUITests/ParkAlongUITests.swift
git commit -m "feat: modernize map controls for Liquid Glass"
```

### Task 4: Modernize search and detail navigation, including iOS 27 beta behavior

**Files:**
- Modify: `ParkAlong/Features/Search/DestinationSearchView.swift`
- Modify: `ParkAlong/Features/ZoneDetail/ZoneDetailView.swift`
- Modify: `ParkAlong/Features/Map/MapControls.swift`
- Modify: `ParkAlong/DesignSystem/AdaptiveChrome.swift`
- Modify: `ParkAlongUITests/ParkAlongUITests.swift`

**Interfaces:**
- Consumes: `ParkingMapViewModel.search`, `chooseDestination`, `navigate`, iOS 27 wrapper modifiers, and existing fixture identifiers.
- Produces: native search presentation, pinned Cancel/Done/current-location actions on iOS 27, toolbar overflow for About, minimizing scroll chrome, and adaptive status-bar contrast.

- [ ] **Step 1: Add failing UI assertions for the redesigned navigation contract**

Extend the existing search test to assert a `destination-search-container` identifier and a hittable Cancel action. Extend the navigation test to assert `navigate-button` remains hittable at the medium detent.

- [ ] **Step 2: Run the focused search and navigation tests and verify RED**

Expected: search fails because the new container identifier is absent; existing behavior remains otherwise intact.

- [ ] **Step 3: Resume Cursor for the bounded search/detail task**

Run Cursor with `cursor-grok-4.6-high` and the same safeguards as Task 3. Require it to use `topBarPinnedTrailing`, `visibilityPriority(.high)`, `ToolbarOverflowMenu`, `toolbarMinimizationBehavior`, and status-bar toolbar color scheme only inside Xcode 27 compiler/runtime gates, with equivalent iOS 17–26 actions.

- [ ] **Step 4: Review and correct the iOS 27 boundaries**

Build with Xcode 26 first to prove excluded iOS 27 symbols do not leak into the stable path. Then build with Xcode 27 to catch renamed beta APIs. Use Apple’s current iOS 27 release notes as the authority if the beta SDK spelling differs from the plan.

- [ ] **Step 5: Verify GREEN for all UI tests**

Run all `ParkAlongUITests`. Expected: zero failures, with existing fixture-error, location-denied, duration-menu, static-pin, and navigation coverage preserved.

- [ ] **Step 6: Commit search and detail modernization**

```bash
git add ParkAlong/Features/Search ParkAlong/Features/ZoneDetail ParkAlong/Features/Map/MapControls.swift ParkAlong/DesignSystem/AdaptiveChrome.swift ParkAlongUITests/ParkAlongUITests.swift
git commit -m "feat: adopt modern search and detail chrome"
```

### Task 5: Move CI to iOS 26 and add an iOS 27 compile gate

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: stable `macos-26` full-test job and required `xcode-27` build-only compatibility job.
- Consumes: generated `ParkAlong.xcodeproj` and dynamically discovered simulator/runtime identifiers.

- [ ] **Step 1: Change the stable runner to `macos-26`**

Keep dynamic simulator creation, print `xcodebuild -version`, and run the full Swift test suite with `CODE_SIGNING_ALLOWED=NO`.

- [ ] **Step 2: Make generator tests independently observable**

Add `if: ${{ always() }}` to the generator-test step so Python failures are reported even if the Swift test step fails.

- [ ] **Step 3: Add the Xcode 27 build-only job**

Use `runs-on: xcode-27`, install XcodeGen, generate the project, print the active Xcode version, dynamically select an iOS simulator destination, and run:

```bash
xcodebuild build-for-testing \
  -project ParkAlong.xcodeproj \
  -scheme ParkAlong \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 4: Validate workflow syntax and local commands**

Inspect the YAML diff, run the stable local build command, and run `git diff --check`.

- [ ] **Step 5: Commit the CI upgrade**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: test iOS 26 and compile iOS 27"
```

### Task 6: Regenerate, run the full verification matrix, and refresh screenshots

**Files:**
- Regenerate: `ParkAlong.xcodeproj/project.pbxproj`
- Update: `docs/images/parkalong-main-light.png`
- Update: `docs/images/parkalong-main-dark.png`
- Update: `docs/images/parkalong-search-dark.png`
- Update: `docs/images/parkalong-selected-zone-dark.png`

**Interfaces:**
- Consumes: completed SwiftUI implementation and UI-test fixtures.
- Produces: checked-in generated project and current visual documentation.

- [ ] **Step 1: Regenerate from the source-of-truth spec**

Run `/opt/homebrew/bin/xcodegen generate --spec project.yml` and verify that no nested `ParkAlong.xcodeproj/ParkAlong.xcodeproj` exists.

- [ ] **Step 2: Run all automated checks with Xcode 26**

Run the complete Swift unit/UI suite, `python3 -m unittest discover -s Scripts/tests -v`, `python3 -m compileall -q Scripts`, and `git diff --check`.

- [ ] **Step 3: Run the Xcode 27 build and focused tests**

Set `DEVELOPER_DIR` to the Xcode 27 beta developer directory, regenerate, run `build-for-testing`, and run the adaptive chrome plus map/search UI tests on an iOS 27 simulator.

- [ ] **Step 4: Inspect accessibility configurations**

Launch fixture builds in light mode, dark mode, an accessibility Dynamic Type size, Reduce Motion, and Reduce Transparency. Confirm controls remain visible, readable, and hittable.

- [ ] **Step 5: Capture and inspect the four README screenshots**

Capture the main light, main dark, search dark, and selected-zone dark states at the existing filenames. Inspect each image before accepting it.

- [ ] **Step 6: Commit generated and visual artifacts**

```bash
git add ParkAlong.xcodeproj docs/images
git commit -m "docs: refresh ParkAlong interface previews"
```

### Task 7: Push, verify GitHub CI, and install on the physical iPhone

**Files:**
- No new source files expected.

**Interfaces:**
- Consumes: signed ParkAlong app product and paired device identifier `FE6FDA0E-7464-59A9-9233-5B96F9DB8A12`.
- Produces: green GitHub run plus verified installed and launched app on `Sidhaarth’s iPhone`.

- [ ] **Step 1: Re-read the spec and inspect the final diff**

Confirm every approved requirement is represented and no excluded feature was added. Run `git status`, `git diff origin/main...HEAD --check`, and inspect the commit list.

- [ ] **Step 2: Push `main` and monitor the new CI run**

Push the completed commits, locate the run for the pushed SHA with `gh run list`, and wait until both stable and iOS 27 jobs finish. If either fails, inspect the exact logs, reproduce, fix by root cause, and repeat.

- [ ] **Step 3: Build a signed Debug device app with Xcode 27**

Run `xcodebuild` for the physical device destination using automatic signing, `DEVELOPMENT_TEAM=2627C3S7CG`, and a dedicated DerivedData path. Resolve the exact `.app` path from the build settings rather than guessing it.

- [ ] **Step 4: Install over the local network**

Run:

```bash
xcrun devicectl device install app \
  --device FE6FDA0E-7464-59A9-9233-5B96F9DB8A12 \
  /absolute/path/from/the/device/build/ParkAlong.app
```

- [ ] **Step 5: Launch and confirm the process**

Run:

```bash
xcrun devicectl device process launch \
  --device FE6FDA0E-7464-59A9-9233-5B96F9DB8A12 \
  com.sidkrishnan.ParkAlong
```

Then list device applications/processes to confirm installation and launch. Capture a device screenshot when possible and inspect it for the final iOS 27 appearance.

- [ ] **Step 6: Report evidence, not assumptions**

Report exact test counts, GitHub run URL/status, Xcode versions used, physical device OS, install result, launch result, and any remaining beta-only limitation.

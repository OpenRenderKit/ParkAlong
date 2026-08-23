# ParkAlong iOS 26/27 Liquid Glass Upgrade Design

## Goal

Modernize ParkAlong into a native-first iOS 26/27 map experience while retaining iOS 17 as the minimum deployment target. The redesign must make the shortest path—choose a destination, understand the best trustworthy parking option, and open navigation—faster and clearer. It must also restore green CI and finish with the app installed and launched on Sidhaarth’s paired iPhone 17 Pro.

## Approved Scope

The app remains map-first. This upgrade includes:

- Native Liquid Glass controls and navigation surfaces on iOS 26 and later.
- Purposeful iOS 27 beta behavior for toolbar priority, pinned actions, minimizing navigation chrome, status-bar contrast, and resizable iPhone windows.
- Carefully matched material-backed controls on iOS 17 through iOS 25.
- Faster destination search, duration filtering, best-option selection, refresh feedback, parking-detail review, and navigation handoff.
- Clearer distinctions between verified live availability, predictions, and location-only data.
- Accessibility, motion, contrast, and Dynamic Type improvements.
- A deterministic fix for the current CI time-zone failures.
- Stable Xcode 26 testing plus an Xcode 27 source-compatibility build.
- Physical installation and launch verification on Sidhaarth’s iPhone 17 Pro.

This upgrade deliberately excludes a map/list switcher, side-by-side parking comparison, favourites, recent destinations, accounts, and persisted user preferences.

## Platform Strategy

`project.yml` remains the source of truth and keeps `iOS: "17.0"` as the deployment target.

The stable implementation is compiled with the installed Xcode 26 toolchain. iOS 26 Liquid Glass APIs are isolated behind availability checks so the same app binary uses:

- Native Liquid Glass on iOS 26 and iOS 27.
- Standard SwiftUI materials, shapes, and button styles on iOS 17 through iOS 25.
- More opaque surfaces when Reduce Transparency is enabled.

The implementation uses a small set of Xcode 27-only SwiftUI APIs where they improve the existing product flow. Those source paths are compiled with Xcode 27 beta and availability-gated for iOS 27, while equivalent iOS 17–26 toolbar behavior remains present. Xcode 27 is also used in CI as a source-compatibility gate because it changes SwiftUI’s `State` and result-builder implementation. The stable Xcode 26 build remains a required gate for the iOS 17–26 path, and the Xcode 27 build plus the paired iOS 27 phone verify the beta path.

## iOS 27-Specific Behavior

The beta APIs are used conservatively because Apple can still change them before the final release:

- The current-location action uses `topBarPinnedTrailing` so the key map-recovery action remains visible as toolbar space changes.
- The destination/search action receives high toolbar visibility priority so it remains available ahead of secondary actions.
- About moves into `ToolbarOverflowMenu` on iOS 27, keeping the main map toolbar focused without deleting access to provenance and privacy information.
- Search and About navigation bars use `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` so scrolling results or documentation yields more content space. The implementation uses the renamed API documented in the current iOS 27 beta release notes, not the superseded `toolbarMinimizeBehavior` spelling.
- The map sets an explicit status-bar color scheme through the iOS 27 status-bar toolbar placement so status information remains legible over map imagery.
- Layouts respond to available container width rather than fixed screen assumptions, supporting iOS 27 resizable iPhone app windows and iPhone Mirroring.

No document, drag-and-drop, tab-role, or image-caching API is added because those iOS 27 features do not serve ParkAlong’s approved find-and-navigate flow.

## Design Principles

Liquid Glass is a functional layer, not the content background. Glass is reserved for controls that float over the map, navigation actions, and the primary call to action. Parking facts, warnings, source attribution, and legal guidance use solid or standard-material content surfaces for dependable contrast.

System components are preferred over hand-built imitations. Custom glass is limited to the compact map controls that have no direct system equivalent. Nearby custom glass controls share one `GlassEffectContainer` on iOS 26 and later, ensuring they sample the same background and animate coherently.

Color continues to communicate parking meaning rather than decoration:

- Green, amber, and red remain reserved for verified live availability.
- Plum remains the prediction color and always appears with estimate wording.
- Location-only data stays neutral/red with an explicit non-live warning.
- Tint is used only for selection and the primary navigation action.

## Map Screen

The map remains edge-to-edge and visually dominant.

### Destination Control

The current wide top card becomes native toolbar content with a compact destination control group:

- The destination name and subtitle form one large, tappable search target.
- Search uses the magnifying-glass symbol and the existing `destination-search-button` test identifier.
- Current location is a separate 44-point action with selected-state feedback.
- About remains a secondary icon action on iOS 17–26 and moves into the iOS 27 toolbar overflow menu.
- Standard toolbar placement supplies native Liquid Glass on iOS 26/27 and the appropriate system bar appearance on iOS 17–25.
- The destination action remains high priority on iOS 27, while current location uses the pinned trailing placement.
- Long destination names wrap without pushing icon targets below 44 points.

### Parking Markers

Map annotations remain semantic, compact, and non-glass. Their count or `P` label stays legible against both map appearances. Selection grows the marker slightly, adds a stronger outline, and respects Reduce Motion. Non-live markers retain the warning badge and accessibility wording.

### Bottom Control Layer

The bottom area becomes one coherent hierarchy instead of unrelated floating cards:

1. A small status element communicates loading, failure, data mode, and freshness.
2. The best verified option appears as the primary contextual action when available.
3. Stay-duration choices and refresh form a compact control dock.

On iOS 26+, the best-option action and duration dock use native interactive glass and coordinated transitions. The best-option action may use semantic availability tint, while the dock remains neutral. On older systems, the same layout uses material surfaces. Loading disables duplicate refresh work, and failure keeps an explicit retry action in reach.

The primary duration choices remain 15 minutes, 1 hour, 2 hours, and 3 hours. Longer durations remain in the existing More menu to avoid adding density. The selected duration must have more than a color-only distinction and retain the existing accessibility identifiers.

## Destination Search

Search remains a modal `NavigationStack`, but its layout follows native search conventions:

- A system search presentation or standard search field receives focus on entry.
- Results use native list rows with a clear name/subtitle hierarchy and full-width 44-point targets.
- Empty, searching, and no-result states are explicit.
- Selecting a result dismisses search, moves the map camera, and refreshes parking once.
- Cancel never changes the current destination.
- Existing deterministic UI-test fixtures and identifiers remain supported.

## Parking Detail Sheet

Selecting any parking marker opens the existing detent sheet. The information order is optimized for a quick decision:

1. Data-quality warning when the option is not verified live.
2. Parking name, type, and walking distance.
3. Availability or estimate, time limit, and price.
4. Prediction confidence when present.
5. Source and freshness details.
6. Posted-sign disclaimer.

The sheet uses the system presentation surface, which naturally adopts the current platform appearance. Fact cards do not receive Liquid Glass. The bottom Navigate action remains visible using `safeAreaInset`; it uses a prominent glass button on iOS 26+ and a bordered-prominent system button on older systems. Navigation interception used by UI tests remains unchanged.

## Adaptive Glass Boundary

A small shared SwiftUI compatibility layer owns platform styling so availability checks are not duplicated across feature files. It provides:

- An adaptive interactive glass surface for custom map controls.
- An adaptive prominent action style.
- A coordinated container that becomes `GlassEffectContainer` on iOS 26+ and a normal layout container on older systems.
- A high-legibility fallback when Reduce Transparency is enabled.
- iOS 27 toolbar placement, priority, minimization, overflow, and status-bar wrappers with iOS 17–26 equivalents.

This layer owns presentation only. It must not contain parking data, selection, refresh, or navigation logic.

## Functional Behavior and Data Flow

The existing `ParkingMapViewModel` remains the single UI state owner.

1. App launch resolves location or the default Melbourne CBD destination.
2. A refresh requests live, off-street, and static sources through existing services.
3. Results are ranked and marked as verified live, predicted, or location-only.
4. Map controls render loading, failure, freshness, duration, and best-option state.
5. Selecting an option loads any bay detail and presents the sheet.
6. Navigate hands the selected coordinate to Apple Maps.

The UI redesign must not duplicate repository logic or infer live status from appearance. Existing fail-closed classifications and provenance remain authoritative.

## Error Handling

- Initial and manual refreshes show an explicit progress state without stacking tasks.
- A total data failure shows a human-readable error and Retry.
- Partial-source failures retain usable results and keep the existing notice describing their quality.
- Location denial keeps destination search and the default CBD usable.
- Search cancellation and empty search results never clear the current map state.
- Navigation remains disabled only when no option is selected.
- Glass availability never controls functionality; older systems always receive an equivalent action.

## Accessibility and Interaction

- All interactive controls have a minimum 44-by-44-point hit region.
- Dynamic Type, including accessibility sizes, may reflow controls vertically without truncating meaning.
- VoiceOver labels include availability classification, values, and action purpose.
- Reduce Motion removes scale/morph animations while preserving state changes.
- Reduce Transparency replaces translucent control backgrounds with a legible opaque system background.
- Status and selection never rely on color alone.
- Haptics remain lightweight and correspond only to selection or successful action changes.

## CI Failure and CI Upgrade

The current GitHub failure is deterministic: `ParkingRuleResolver.formattedTime` builds a Melbourne-local `Date` and then formats it with a style that falls back to the host time zone. GitHub’s UTC runner therefore prints Melbourne schedule boundaries as UTC. The fix must set the formatter’s calendar, locale, and `Australia/Melbourne` time zone explicitly at the formatting boundary. Existing assertions become the regression coverage; tests must also be runnable under a UTC environment.

The workflow moves its full build, unit tests, and UI tests from `macos-15`/Xcode 16.4 to `macos-26`, whose default Xcode supports the iOS 26 APIs. A second required build-only job uses GitHub’s `xcode-27` public-preview runner to compile the iOS 17-deployment-target source against the iOS 27 SDK. Generator tests remain in the stable job and must run even if Swift tests fail, so independent failures are visible.

## Cursor UI Work Contract

UI implementation is delegated through Cursor Agent CLI using the exact model `cursor-grok-4.6-high`, not the `-fast` variant. Cursor works in the current workspace and may edit only the approved UI, UI tests, and shared adaptive-style files. Its prompt must forbid unrelated reversions and require a summary of files changed, checks run, assumptions, and blockers.

Cursor output is treated as a draft. The parent agent reviews every diff, corrects architecture and accessibility issues, keeps business logic out of presentation helpers, and runs all verification independently.

## Verification

Implementation is accepted only after fresh evidence for all of the following:

- `xcodegen generate --spec project.yml` succeeds without creating a nested project.
- Focused regression tests pass in a UTC-sensitive configuration.
- All Swift unit and UI tests pass on an iPhone 17 Pro simulator using Xcode 26.
- All Python generator tests pass.
- Python scripts compile with `compileall`.
- `git diff --check` passes.
- Light mode, dark mode, a large Dynamic Type size, Reduce Motion, and Reduce Transparency receive targeted UI inspection.
- A release-style device build signs for `com.sidkrishnan.ParkAlong`.
- The app installs and launches on the paired device named `Sidhaarth’s iPhone` over the local network.
- Device installation is confirmed by `devicectl`, and launch is confirmed by a successful process launch rather than an assumption from build output.

## Delivery Constraints

- Preserve the exact ParkAlong name and bundle identifier.
- Preserve iOS 17 as the minimum deployment target.
- Do not add third-party UI dependencies.
- Do not add excluded comparison or personalization features.
- Do not weaken live/static/prediction truthfulness.
- Do not claim the iOS 27 beta path works until it compiles with Xcode 27 and launches on the iOS 27 device.
- Do not claim CI success until a fresh GitHub run is green.
- Do not claim device delivery until installation and launch both succeed.

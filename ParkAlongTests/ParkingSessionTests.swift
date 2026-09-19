import XCTest
@testable import ParkAlong

@MainActor
final class ParkingSessionTests: XCTestCase {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Explicit parked transition

    func testSessionStartsEnRouteAndOnlyMarksParkedExplicitly() {
        let now = Self.fixedNow
        var session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 120),
            createdAt: now
        )

        XCTAssertEqual(session.phase, .enRoute)
        XCTAssertNil(session.parkedAt)
        XCTAssertNil(session.plannedDeparture)
        XCTAssertNil(session.activityState.parkedAt)
        XCTAssertNil(session.activityState.plannedDeparture)
        XCTAssertEqual(session.activityState.phase, .enRoute)

        session.markParked(at: now.addingTimeInterval(300))

        XCTAssertEqual(session.phase, .parked)
        XCTAssertEqual(session.parkedAt, now.addingTimeInterval(300))
        XCTAssertEqual(session.plannedDeparture, now.addingTimeInterval(7_500))
        XCTAssertEqual(session.activityState.phase, .parked)
        XCTAssertEqual(session.activityState.parkedAt, now.addingTimeInterval(300))
        XCTAssertEqual(session.activityState.plannedDeparture, now.addingTimeInterval(7_500))
    }

    func testNavigateLeavesSessionEnRouteUntilExplicitMarkParked() async {
        let now = Self.fixedNow
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))

        await viewModel.navigate()

        XCTAssertEqual(viewModel.parkingSession?.phase, .enRoute)
        XCTAssertNil(viewModel.parkingSession?.parkedAt)
        XCTAssertNil(viewModel.parkingSession?.plannedDeparture)
        XCTAssertEqual(store.load()?.phase, .enRoute)
        XCTAssertNil(store.load()?.parkedAt)
        XCTAssertNil(store.load()?.plannedDeparture)

        await viewModel.markParked(at: now)

        XCTAssertEqual(viewModel.parkingSession?.phase, .parked)
        XCTAssertEqual(viewModel.parkingSession?.parkedAt, now)
        XCTAssertEqual(
            viewModel.parkingSession?.plannedDeparture,
            now.addingTimeInterval(TimeInterval(60 * 60))
        )
        // Default plan in the view model is a one-hour stay.
        XCTAssertEqual(store.load()?.parkedAt, now)
    }

    func testMarkParkedWithoutSessionIsNoop() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)

        await viewModel.markParked(at: Self.fixedNow)

        XCTAssertNil(viewModel.parkingSession)
        XCTAssertNil(store.load())
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertTrue(activity.updatedSessions.isEmpty)
    }

    // MARK: - Activity start ordering and non-blocking behaviour

    func testLiveActivityFailureNeverBlocksNavigation() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .disabled, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .staticOnly))

        await viewModel.navigate()

        XCTAssertEqual(events.values, ["activity-start", "navigate"])
        XCTAssertEqual(viewModel.liveActivityStartOutcome, .disabled)
        XCTAssertTrue(viewModel.navigationWasIntercepted)
        XCTAssertFalse(viewModel.navigationHandoffFailed)
        XCTAssertNotNil(store.load())
        XCTAssertNotNil(viewModel.parkingSession)
        XCTAssertEqual(viewModel.parkingSession?.phase, .enRoute)
        XCTAssertEqual(activity.startedSessions.count, 1)
        XCTAssertTrue(activity.endedSessionIDs.isEmpty)
    }

    func testUnavailableActivityNeverBlocksNavigation() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .unavailable, events: events)
        let navigator = RecordingParkingNavigator(result: .opened, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .predicted))

        await viewModel.navigate()

        // Start is still attempted first even though ActivityKit cannot present.
        XCTAssertEqual(events.values, ["activity-start", "navigate"])
        XCTAssertEqual(viewModel.liveActivityStartOutcome, .unavailable)
        XCTAssertFalse(viewModel.navigationWasIntercepted)
        XCTAssertFalse(viewModel.navigationHandoffFailed)
        XCTAssertNotNil(viewModel.parkingSession)
        XCTAssertNotNil(store.load())
        XCTAssertTrue(activity.endedSessionIDs.isEmpty)
    }

    func testStartedActivityAttemptsStartBeforeMaps() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))

        await viewModel.navigate()

        XCTAssertEqual(events.values, ["activity-start", "navigate"])
        XCTAssertEqual(viewModel.liveActivityStartOutcome, .started)
        XCTAssertEqual(activity.startedSessions.count, 1)
        XCTAssertFalse(viewModel.navigationHandoffFailed)
        XCTAssertNotNil(viewModel.parkingSession)
    }

    // MARK: - Maps failure cleanup

    func testFailedMapsHandoffEndsActivityAndClearsSession() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .failed, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))

        await viewModel.navigate()

        XCTAssertEqual(events.values, ["activity-start", "navigate", "activity-end"])
        XCTAssertTrue(viewModel.navigationHandoffFailed)
        XCTAssertFalse(viewModel.navigationWasIntercepted)
        XCTAssertNil(viewModel.parkingSession)
        XCTAssertNil(store.load())
        XCTAssertEqual(activity.endedSessionIDs.count, 1)
        XCTAssertNil(viewModel.liveActivityStartOutcome)
    }

    func testReplacingSessionCancelsPriorReminderAndFailureClearsOutcome() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = MutableRecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let reminders = RecordingParkingReminderScheduler()
        let viewModel = makeViewModel(
            navigator: navigator,
            store: store,
            activity: activity,
            reminderScheduler: reminders
        )
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))
        await viewModel.navigate()
        let priorSessionID = viewModel.parkingSession!.id
        XCTAssertEqual(viewModel.liveActivityStartOutcome, .started)

        navigator.result = .failed
        viewModel.selectOffStreet(makeOption(classification: .predicted))
        await viewModel.navigate()

        XCTAssertTrue(reminders.cancelledSessionIDs.contains(priorSessionID))
        XCTAssertTrue(viewModel.navigationHandoffFailed)
        XCTAssertNil(viewModel.parkingSession)
        XCTAssertNil(store.load())
        XCTAssertNil(viewModel.liveActivityStartOutcome)
    }

    func testFailedMapsHandoffClearsSessionEvenWhenActivityDisabled() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .disabled, events: events)
        let navigator = RecordingParkingNavigator(result: .failed, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .staticOnly))

        await viewModel.navigate()

        XCTAssertEqual(events.values, ["activity-start", "navigate"])
        // A failed Maps handoff leaves no session behind, so the stale start
        // outcome is reset rather than kept.
        XCTAssertNil(viewModel.liveActivityStartOutcome)
        XCTAssertTrue(viewModel.navigationHandoffFailed)
        XCTAssertNil(viewModel.parkingSession)
        XCTAssertNil(store.load())
        XCTAssertTrue(activity.endedSessionIDs.isEmpty)
    }

    func testMarkParkedPersistsAndUpdatesActivity() async {
        let now = Self.fixedNow
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))
        await viewModel.navigate()

        await viewModel.markParked(at: now)

        XCTAssertEqual(viewModel.parkingSession?.phase, .parked)
        XCTAssertEqual(store.load()?.parkedAt, now)
        XCTAssertEqual(
            store.load()?.plannedDeparture,
            now.addingTimeInterval(TimeInterval(60 * 60))
        )
        XCTAssertEqual(events.values, ["activity-start", "navigate", "activity-update"])
        XCTAssertEqual(events.values.last, "activity-update")
        XCTAssertEqual(activity.updatedSessions.count, 1)
        XCTAssertEqual(activity.updatedSessions.first?.parkedAt, now)
    }

    // MARK: - Availability honesty

    func testObservedAvailabilityBecomesStaleFiveMinutesAfterSnapshot() {
        let snapshot = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .verifiedLive, sourceTimestamp: snapshot),
            plan: .init(arrival: snapshot, durationMinutes: 60),
            createdAt: snapshot
        )

        XCTAssertEqual(session.availabilityKind, .observed)
        XCTAssertEqual(session.activityStaleDate, snapshot.addingTimeInterval(300))
        XCTAssertEqual(session.activityState.availability.kind, .observed)
        XCTAssertEqual(session.activityState.availability.available, 4)
        XCTAssertEqual(session.activityState.availability.total, 7)
        XCTAssertEqual(session.activityState.availability.snapshotAt, snapshot)
    }

    func testPredictedAvailabilityIsEstimatedWithoutStaleDate() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .predicted, sourceTimestamp: nil),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )

        XCTAssertEqual(session.availabilityKind, .estimated)
        XCTAssertEqual(session.activityState.availability.kind, .estimated)
        XCTAssertNil(session.activityStaleDate)
        XCTAssertEqual(session.activityState.availability.available, 4)
        XCTAssertEqual(session.activityState.availability.total, 7)
    }

    func testStaleHistoricalNeverCreatesObservedAvailability() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .staleHistorical, available: nil, total: nil, sourceTimestamp: nil),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )

        XCTAssertEqual(session.availabilityKind, .unavailable)
        XCTAssertNil(session.activityStaleDate)
        XCTAssertNil(session.activityState.availability.available)
        XCTAssertEqual(session.activityState.availability.kind, .unavailable)
    }

    func testStaticParkingNeverCreatesObservedAvailability() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .staticOnly, available: nil, total: nil, sourceTimestamp: nil),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )

        XCTAssertEqual(session.availabilityKind, .unavailable)
        XCTAssertNil(session.activityStaleDate)
        XCTAssertNil(session.activityState.availability.available)
        XCTAssertEqual(session.activityState.availability.kind, .unavailable)
    }

    func testAvailabilityCopyRemainsHonest() {
        let observed = ParkingActivityAvailability(
            kind: .observed, available: 4, total: 7,
            snapshotAt: Self.fixedNow, sourceCheckedAt: Self.fixedNow
        )
        let estimated = ParkingActivityAvailability(
            kind: .estimated, available: 3, total: 7,
            snapshotAt: nil, sourceCheckedAt: Self.fixedNow
        )
        let unavailable = ParkingActivityAvailability(
            kind: .unavailable, available: nil, total: nil,
            snapshotAt: nil, sourceCheckedAt: Self.fixedNow
        )

        XCTAssertTrue(ParkingActivityCopy.availabilityText(observed).contains("observed"))
        XCTAssertTrue(ParkingActivityCopy.availabilityText(observed).contains("4 of 7"))
        XCTAssertTrue(ParkingActivityCopy.availabilityText(estimated).contains("estimate"))
        XCTAssertEqual(ParkingActivityCopy.availabilityText(unavailable), "Availability unavailable")
        XCTAssertEqual(ParkingActivityCopy.compactAvailability(observed), "4")
        XCTAssertEqual(ParkingActivityCopy.compactAvailability(estimated), "~3")
        XCTAssertEqual(ParkingActivityCopy.compactAvailability(unavailable), "P")
        XCTAssertTrue(
            ParkingActivityCopy.availabilityText(observed, isStale: true).contains("out of date")
        )
        XCTAssertFalse(
            ParkingActivityCopy.availabilityText(observed).localizedCaseInsensitiveContains("out of date")
        )
    }

    func testObservedAvailabilityCopyMarksFiveMinuteStaleSnapshots() {
        let snapshot = Self.fixedNow
        let observed = ParkingActivityAvailability(
            kind: .observed, available: 4, total: 7,
            snapshotAt: snapshot, sourceCheckedAt: snapshot
        )
        let estimated = ParkingActivityAvailability(
            kind: .estimated, available: 3, total: 7,
            snapshotAt: snapshot.addingTimeInterval(-600), sourceCheckedAt: snapshot
        )
        let justBefore = snapshot.addingTimeInterval(299)
        let atThreshold = snapshot.addingTimeInterval(300)

        XCTAssertFalse(ParkingActivityCopy.isObservedAvailabilityStale(observed, now: snapshot))
        XCTAssertFalse(ParkingActivityCopy.isObservedAvailabilityStale(observed, now: justBefore))
        XCTAssertTrue(ParkingActivityCopy.isObservedAvailabilityStale(observed, now: atThreshold))
        XCTAssertFalse(ParkingActivityCopy.isObservedAvailabilityStale(estimated, now: atThreshold))
        XCTAssertEqual(
            ParkingActivityCopy.availabilityText(
                observed,
                isStale: ParkingActivityCopy.isObservedAvailabilityStale(observed, now: justBefore)
            ).contains("out of date"),
            false
        )
        XCTAssertTrue(
            ParkingActivityCopy.availabilityText(
                observed,
                isStale: ParkingActivityCopy.isObservedAvailabilityStale(observed, now: atThreshold)
            ).contains("out of date")
        )
    }

    func testParkedStaleDateEqualsPlannedDeparture() {
        let now = Self.fixedNow
        var session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 120),
            createdAt: now
        )
        session.markParked(at: now)

        XCTAssertEqual(session.activityStaleDate, session.plannedDeparture)
        XCTAssertEqual(session.activityStaleDate, now.addingTimeInterval(TimeInterval(120 * 60)))
    }

    // MARK: - Privacy

    func testPrivacyDefaultsHiddenAndUpdatesPersist() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))
        await viewModel.navigate()

        XCTAssertEqual(viewModel.parkingSession?.showsPreciseLocation, false)
        XCTAssertEqual(
            ParkingActivityCopy.displayTitle(for: viewModel.parkingSession!.activityState),
            ParkingActivityCopy.hiddenLocationTitle
        )
        XCTAssertNil(ParkingActivityCopy.displayLocation(for: viewModel.parkingSession!.activityState))
        XCTAssertEqual(store.load()?.showsPreciseLocation, false)

        await viewModel.setShowsPreciseLocation(true)

        XCTAssertEqual(viewModel.parkingSession?.showsPreciseLocation, true)
        XCTAssertEqual(store.load()?.showsPreciseLocation, true)
        XCTAssertEqual(
            ParkingActivityCopy.displayTitle(for: viewModel.parkingSession!.activityState),
            viewModel.parkingSession!.parkingTitle
        )
        XCTAssertNotNil(ParkingActivityCopy.displayLocation(for: viewModel.parkingSession!.activityState))
        XCTAssertEqual(events.values.last, "activity-update")
        XCTAssertEqual(activity.updatedSessions.last?.showsPreciseLocation, true)

        await viewModel.setShowsPreciseLocation(false)

        XCTAssertEqual(viewModel.parkingSession?.showsPreciseLocation, false)
        XCTAssertEqual(store.load()?.showsPreciseLocation, false)
        XCTAssertNil(ParkingActivityCopy.displayLocation(for: viewModel.parkingSession!.activityState))
        XCTAssertEqual(activity.updatedSessions.count, 2)
    }

    func testSetPrivacyWithoutSessionIsNoop() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let viewModel = makeViewModel(
            navigator: navigator,
            store: InMemoryParkingSessionStore(),
            activity: activity
        )

        await viewModel.setShowsPreciseLocation(true)

        XCTAssertTrue(events.values.isEmpty)
        XCTAssertTrue(activity.updatedSessions.isEmpty)
    }

    // MARK: - Long stays

    func testLongStayIdentification() {
        let now = Self.fixedNow
        let eightHours = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 480),
            createdAt: now
        )
        let justOverEightHours = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 481),
            createdAt: now
        )
        let twelveHours = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 720),
            createdAt: now
        )

        XCTAssertFalse(eightHours.activityState.isLongStay)
        XCTAssertTrue(justOverEightHours.activityState.isLongStay)
        XCTAssertTrue(twelveHours.activityState.isLongStay)
        XCTAssertFalse(ParkingActivityAttributes.ContentState.previewParked.isLongStay)
        XCTAssertTrue(ParkingActivityAttributes.ContentState.previewParkedLongStay.isLongStay)
    }

    // MARK: - Payload size

    func testActivityPayloadStaysUnderPlatformLimit() throws {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .predicted, sourceTimestamp: now),
            plan: .init(arrival: now, durationMinutes: 7 * 24 * 60),
            createdAt: now
        )
        let encoder = JSONEncoder()
        let attributes = try encoder.encode(ParkingActivityAttributes(sessionID: session.id.uuidString))
        let state = try encoder.encode(session.activityState)

        XCTAssertLessThan(attributes.count + state.count, 4_096)
    }

    func testParkedPayloadStaysUnderPlatformLimit() throws {
        let now = Self.fixedNow
        var session = ParkingSession(
            // Maximum supported duration keeps the encoded departure inside the payload.
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 7 * 24 * 60),
            createdAt: now
        )
        session.markParked(at: now)
        let encoder = JSONEncoder()
        let attributes = try encoder.encode(ParkingActivityAttributes(sessionID: session.id.uuidString))
        let state = try encoder.encode(session.activityState)

        XCTAssertLessThan(attributes.count + state.count, 4_096)
        XCTAssertTrue(session.activityState.isLongStay)
        XCTAssertEqual(session.activityStaleDate, session.plannedDeparture)
    }

    func testAdversarialRemoteTextStaysUnderPayloadLimit() throws {
        let now = Self.fixedNow
        // Very long + adversarial: ASCII flood, CJK/emoji (multi-byte UTF-8),
        // quotes/backslashes (JSON escaping worst case), controls, bidi
        // overrides, zero-width/format characters, and combining marks.
        let longASCII = String(repeating: "A", count: 20_000)
        let longEmoji = String(repeating: "🅿️", count: 5_000)
        let quotes = String(repeating: "\"\\", count: 5_000)
        let adversarialControls = "\0\u{01}\u{02}\u{7F}\u{80}\u{9F}\n\r\t"
            + "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2069}\u{200B}\u{200C}\u{200D}\u{FEFF}"
            + String(repeating: "e\u{301}", count: 2_000)
        let session = ParkingSession(
            option: makeOption(
                classification: .verifiedLive,
                title: longASCII + longEmoji + quotes + adversarialControls,
                locationLabel: longEmoji + longASCII + quotes + adversarialControls,
                restrictionLabel: quotes + longASCII + adversarialControls,
                pricePrimaryText: longASCII + quotes + adversarialControls
            ),
            plan: .init(arrival: now, durationMinutes: 7 * 24 * 60),
            createdAt: now
        )

        // The stored session preserves complete remote strings.
        XCTAssertGreaterThan(session.parkingTitle.utf8.count, 20_000)
        XCTAssertGreaterThan(session.locationLabel.utf8.count, 20_000)

        // The activity copy is bounded and sanitized.
        let state = session.activityState
        XCTAssertLessThanOrEqual(state.parkingTitle.utf8.count, ParkingActivityContentBounds.parkingTitleMaxUTF8Bytes)
        XCTAssertLessThanOrEqual(state.locationLabel.utf8.count, ParkingActivityContentBounds.locationLabelMaxUTF8Bytes)
        XCTAssertLessThanOrEqual(state.ruleSummary.utf8.count, ParkingActivityContentBounds.ruleSummaryMaxUTF8Bytes)
        XCTAssertLessThanOrEqual(state.priceSummary.utf8.count, ParkingActivityContentBounds.priceSummaryMaxUTF8Bytes)
        for text in [state.parkingTitle, state.locationLabel, state.ruleSummary, state.priceSummary] {
            XCTAssertFalse(text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }))
            XCTAssertFalse(text.unicodeScalars.contains(where: {
                $0.properties.generalCategory == .format || $0.properties.isDefaultIgnorableCodePoint
            }))
        }

        let encoder = JSONEncoder()
        let attributes = try encoder.encode(ParkingActivityAttributes(sessionID: session.id.uuidString))
        let encodedState = try encoder.encode(state)
        XCTAssertLessThan(attributes.count + encodedState.count, 4_096)
    }

    // MARK: - Persistence and deep links

    func testSessionPersistenceRoundTripsMinimumRecoveryState() {
        let suiteName = "ParkingSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Self.fixedNow
        let session = ParkingSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )

        ParkingSessionPersistence.save(session, to: defaults)

        XCTAssertEqual(ParkingSessionPersistence.load(from: defaults), session)
        ParkingSessionPersistence.clear(from: defaults)
        XCTAssertNil(ParkingSessionPersistence.load(from: defaults))
    }

    func testCorruptPersistedSessionIsDiscarded() {
        let suiteName = "ParkingSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: ParkingSessionPersistence.key)

        XCTAssertNil(ParkingSessionPersistence.load(from: defaults))
        XCTAssertNil(defaults.data(forKey: ParkingSessionPersistence.key))
    }

    func testSessionStoreRoundTripsThroughViewModelLifecycle() async {
        let events = ParkingJourneyEvents()
        let activity = RecordingParkingActivityController(outcome: .started, events: events)
        let navigator = RecordingParkingNavigator(result: .intercepted, events: events)
        let store = InMemoryParkingSessionStore()
        let viewModel = makeViewModel(navigator: navigator, store: store, activity: activity)
        viewModel.selectOffStreet(makeOption(classification: .verifiedLive))
        await viewModel.navigate()
        let sessionID = viewModel.parkingSession!.id

        await viewModel.endParkingSession()

        XCTAssertNil(viewModel.parkingSession)
        XCTAssertNil(store.load())
        XCTAssertEqual(activity.endedSessionIDs, [sessionID])
        XCTAssertFalse(viewModel.isParkingSessionPresented)
        XCTAssertNil(viewModel.liveActivityStartOutcome)
    }

    func testPreloadedStoreRecoversIntoViewModel() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )
        let store = InMemoryParkingSessionStore(session: session)
        let viewModel = makeViewModel(
            navigator: RecordingParkingNavigator(result: .intercepted, events: ParkingJourneyEvents()),
            store: store,
            activity: RecordingParkingActivityController(outcome: .started, events: ParkingJourneyEvents())
        )

        XCTAssertEqual(viewModel.parkingSession, session)
    }

    func testSessionDeepLinksRecoverDetailsAndReturnActions() {
        let id = UUID()
        let details = ParkingSessionDeepLink(url: ParkingSessionDeepLink.url(sessionID: id))
        let returning = ParkingSessionDeepLink(
            url: ParkingSessionDeepLink.url(sessionID: id, action: .returnToCar)
        )

        XCTAssertEqual(details, .init(sessionID: id, action: .details))
        XCTAssertEqual(returning, .init(sessionID: id, action: .returnToCar))
        XCTAssertNil(ParkingSessionDeepLink(url: URL(string: "https://example.com")!))
        XCTAssertNil(ParkingSessionDeepLink(url: URL(string: "parkalong://session/not-a-uuid")!))
        XCTAssertEqual(
            ParkingSessionDeepLink.url(sessionIDString: id.uuidString),
            Optional(ParkingSessionDeepLink.url(sessionID: id))
        )
        XCTAssertNil(ParkingSessionDeepLink.url(sessionIDString: "not-a-uuid"))
    }

    func testDeepLinkDetailsPresentsRecoveredSession() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )
        let store = InMemoryParkingSessionStore(session: session)
        let viewModel = makeViewModel(
            navigator: RecordingParkingNavigator(result: .intercepted, events: ParkingJourneyEvents()),
            store: store,
            activity: RecordingParkingActivityController(outcome: .started, events: ParkingJourneyEvents())
        )

        viewModel.handleParkingSessionURL(ParkingSessionDeepLink.url(sessionID: session.id))

        XCTAssertEqual(viewModel.parkingSession?.id, session.id)
        XCTAssertTrue(viewModel.isParkingSessionPresented)
    }

    func testDeepLinkReturnRecoversAndNavigatesBack() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )
        let events = ParkingJourneyEvents()
        let store = InMemoryParkingSessionStore(session: session)
        let viewModel = makeViewModel(
            navigator: RecordingParkingNavigator(result: .intercepted, events: events),
            store: store,
            activity: RecordingParkingActivityController(outcome: .started, events: ParkingJourneyEvents())
        )

        viewModel.handleParkingSessionURL(
            ParkingSessionDeepLink.url(sessionID: session.id, action: .returnToCar)
        )

        XCTAssertEqual(events.values, ["return"])
        XCTAssertTrue(viewModel.navigationWasIntercepted)
        XCTAssertFalse(viewModel.isParkingSessionPresented)
    }

    func testDeepLinkWithMismatchedSessionIsIgnored() {
        let now = Self.fixedNow
        let session = ParkingSession(
            option: makeOption(classification: .verifiedLive),
            plan: .init(arrival: now, durationMinutes: 60),
            createdAt: now
        )
        let events = ParkingJourneyEvents()
        let store = InMemoryParkingSessionStore(session: session)
        let viewModel = makeViewModel(
            navigator: RecordingParkingNavigator(result: .intercepted, events: events),
            store: store,
            activity: RecordingParkingActivityController(outcome: .started, events: ParkingJourneyEvents())
        )

        viewModel.handleParkingSessionURL(ParkingSessionDeepLink.url(sessionID: UUID()))
        viewModel.handleParkingSessionURL(URL(string: "https://example.com")!)

        XCTAssertFalse(viewModel.isParkingSessionPresented)
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(viewModel.parkingSession?.id, session.id)
    }

    // MARK: - Helpers

    private func makeViewModel(
        navigator: any ParkingNavigating,
        store: any ParkingSessionStoring,
        activity: any ParkingLiveActivityControlling,
        reminderScheduler: any ParkingReminderScheduling = NoopParkingReminderScheduler()
    ) -> ParkingMapViewModel {
        ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: FixtureLocationService(result: .success(.melbourneCBD)),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: navigator,
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: []),
            parkingSessionStore: store,
            liveActivityController: activity,
            reminderScheduler: reminderScheduler
        )
    }

    private func makeOption(
        classification: ParkingDataClassification,
        available: Int? = 4,
        total: Int? = 7,
        sourceTimestamp: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        title: String = "Little Collins Street",
        locationLabel: String = "Little Collins Street · Swanston Street to Russell Street",
        restrictionLabel: String = "Up to 2 hours, meter required",
        pricePrimaryText: String = "$14.00 for 2 hours"
    ) -> ParkingOption {
        .init(
            id: "test-parking",
            kind: .onStreet,
            title: title,
            locationLabel: locationLabel,
            coordinate: .init(latitude: -37.812, longitude: 144.965),
            availabilityState: available.map { $0 > 0 ? .available : .occupied } ?? .unknown,
            available: available,
            total: total,
            restrictionLabel: restrictionLabel,
            restrictionWindow: "Active restriction now",
            activeNow: true,
            price: .init(
                primaryText: pricePrimaryText,
                detail: "Check the meter for the exact bay.",
                provider: "City of Melbourne",
                actionLabel: nil,
                actionURL: nil
            ),
            provider: "City of Melbourne",
            sourceTimestamp: sourceTimestamp,
            proximity: ParkingProximity(
                straightLineMetres: 180,
                reference: .init(coordinate: .init(latitude: -37.812, longitude: 144.965), label: "Test destination")
            ),
            prediction: nil,
            isSuggested: true,
            zoneNumber: 7002,
            classification: classification,
            warningText: nil,
            sourceDatasetAt: nil,
            sourceCheckedAt: sourceTimestamp,
            schedule: [],
            clusterCount: nil,
            clusterViewport: nil
        )
    }
}

@MainActor
private final class ParkingJourneyEvents {
    var values: [String] = []
}

@MainActor
private final class RecordingParkingActivityController: ParkingLiveActivityControlling {
    let outcome: ParkingLiveActivityStartOutcome
    let events: ParkingJourneyEvents
    var startedSessions: [ParkingSession] = []
    var updatedSessions: [ParkingSession] = []
    var endedSessionIDs: [UUID] = []

    init(outcome: ParkingLiveActivityStartOutcome, events: ParkingJourneyEvents) {
        self.outcome = outcome
        self.events = events
    }

    func start(_ session: ParkingSession) async -> ParkingLiveActivityStartOutcome {
        events.values.append("activity-start")
        startedSessions.append(session)
        return outcome
    }

    func update(_ session: ParkingSession) async {
        events.values.append("activity-update")
        updatedSessions.append(session)
    }

    func end(sessionID: UUID) async {
        events.values.append("activity-end")
        endedSessionIDs.append(sessionID)
    }

    func reconcile(with session: ParkingSession?) async {}
}

@MainActor
private final class RecordingParkingReminderScheduler: ParkingReminderScheduling {
    private(set) var cancelledSessionIDs: [UUID] = []

    func schedule(for session: ParkingSession, message: ParkingReminderMessage) async -> ParkingReminderScheduleOutcome {
        .unavailable
    }

    func cancel(sessionID: UUID) {
        cancelledSessionIDs.append(sessionID)
    }
}

@MainActor
private final class MutableRecordingParkingNavigator: ParkingNavigating {
    var result: ParkingNavigationHandoffResult
    let events: ParkingJourneyEvents

    init(result: ParkingNavigationHandoffResult, events: ParkingJourneyEvents) {
        self.result = result
        self.events = events
    }

    func navigate(to zone: ParkingZone) -> ParkingNavigationHandoffResult {
        events.values.append("navigate")
        return result
    }

    func navigate(to option: ParkingOption) -> ParkingNavigationHandoffResult {
        events.values.append("navigate")
        return result
    }

    func returnToParking(_ session: ParkingSession) -> ParkingNavigationHandoffResult {
        events.values.append("return")
        return result
    }
}

@MainActor
private final class RecordingParkingNavigator: ParkingNavigating {
    let result: ParkingNavigationHandoffResult
    let events: ParkingJourneyEvents

    init(result: ParkingNavigationHandoffResult, events: ParkingJourneyEvents) {
        self.result = result
        self.events = events
    }

    func navigate(to zone: ParkingZone) -> ParkingNavigationHandoffResult {
        events.values.append("navigate")
        return result
    }

    func navigate(to option: ParkingOption) -> ParkingNavigationHandoffResult {
        events.values.append("navigate")
        return result
    }

    func returnToParking(_ session: ParkingSession) -> ParkingNavigationHandoffResult {
        events.values.append("return")
        return result
    }
}

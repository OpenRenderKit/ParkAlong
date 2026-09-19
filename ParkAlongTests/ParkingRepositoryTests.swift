import XCTest
@testable import ParkAlong

final class ParkingRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_776_297_600) // Thursday 10am in Melbourne

    func testBundledHistoricalDecodeCostIsRecorded() throws {
        let clock = ContinuousClock()
        var recordCount = 0

        let elapsed = try clock.measure {
            let records = try BundleDataLoader.load([HistoricalBucket].self, named: "historical_availability")
            recordCount = records.count
        }
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        print("PARKALONG_PERF historical_decode_seconds=\(elapsedSeconds) records=\(recordCount)")
        XCTAssertGreaterThan(recordCount, 1_000)
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    func testRefreshJoinsLiveCountsAndAppliesStayAsHardFilter() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7001, status: .unoccupied, bayCount: 5, newestTimestamp: now.addingTimeInterval(-60)),
            .init(zoneNumber: 7001, status: .present, bayCount: 1, newestTimestamp: now.addingTimeInterval(-60)),
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now.addingTimeInterval(-30)),
            .init(zoneNumber: 7002, status: .present, bayCount: 3, newestTimestamp: now.addingTimeInterval(-30))
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7001, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "1P"),
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "MP3P")
        ], history: [])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.twoHours), now: now, force: true
        )

        XCTAssertEqual(result.mode, .live)
        XCTAssertEqual(result.zones.map(\.zoneNumber), [7002])
        XCTAssertEqual(result.zones.first?.available, 2)
        XCTAssertEqual(result.zones.first?.payment, .paid)
        XCTAssertFalse(result.zones.first?.isSuggested == true)
    }

    func testRefreshUsesShortCacheButExpiresAtTwoMinutes() async throws {
        let api = FixtureParkingAPI(rows: [.init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], cacheTTL: 120)

        _ = try await repository.refresh(
            viewport: viewport, proximityReference: reference(), plan: plan(.oneHour), now: now
        )
        _ = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.oneHour), now: now.addingTimeInterval(119)
        )
        let countBeforeExpiry = await api.fetchCount
        XCTAssertEqual(countBeforeExpiry, 1)
        _ = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.oneHour), now: now.addingTimeInterval(120)
        )
        let countAfterExpiry = await api.fetchCount
        XCTAssertEqual(countAfterExpiry, 2)
    }

    func testCancelledRefreshDoesNotDecodeHistoricalFallback() async {
        let api = CancellableParkingAPI()
        let historyLoads = SynchronousCounter()
        let history = [
            HistoricalBucket(
                segmentKey: metadata[1].segmentKey,
                weekday: 5,
                interval: 40,
                occupiedRatio: 0.4,
                turnover: 0.3,
                sampleCount: 800
            )
        ]
        let repository = ParkingRepository(
            api: api,
            metadata: metadata,
            restrictions: [
                .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
            ],
            history: [],
            historyLoader: {
                historyLoads.increment()
                return history
            }
        )
        let clock = ContinuousClock()
        let requestViewport = viewport
        let requestPlan = plan(.oneHour)
        let requestReference = reference()
        let requestNow = now
        let refresh = Task {
            try await repository.refresh(
                viewport: requestViewport,
                proximityReference: requestReference,
                plan: requestPlan,
                now: requestNow,
                force: true
            )
        }
        await api.waitUntilStarted()

        let elapsed = await clock.measure {
            refresh.cancel()
            _ = try? await refresh.value
        }

        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        print("PARKALONG_PERF cancelled_refresh_seconds=\(elapsedSeconds) history_loads=\(historyLoads.value)")
        XCTAssertTrue(refresh.isCancelled)
        XCTAssertEqual(historyLoads.value, 0, "Cancellation must not trigger the 48 MB historical fallback decode")
    }

    func testViewportCacheIsBoundedDuringLongPanSessions() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(
            api: api,
            metadata: metadata,
            restrictions: [
                .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
            ],
            history: []
        )
        let first = viewport

        for index in 0..<40 {
            let offset = Double(index) * 0.01
            let moved = ParkingViewport(
                south: first.south + offset,
                west: first.west + offset,
                north: first.north + offset,
                east: first.east + offset,
                zoomLevel: first.zoomLevel
            )
            _ = try await repository.refresh(
                viewport: moved, proximityReference: reference(),
                plan: plan(.oneHour), now: now
            )
        }
        _ = try await repository.refresh(
            viewport: first, proximityReference: reference(),
            plan: plan(.oneHour), now: now
        )

        let fetchCount = await api.fetchCount
        print("PARKALONG_PERF bounded_cache_requests_after_40_viewports=\(fetchCount)")
        XCTAssertEqual(fetchCount, 41, "The oldest viewport should be evicted instead of retaining an unbounded session cache")
    }

    func testViewportCacheHitRefreshesRecencyBeforeEviction() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(
            api: api,
            metadata: metadata,
            restrictions: [
                .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
            ],
            history: [],
            cacheLimit: 2
        )
        func moved(_ offset: Double) -> ParkingViewport {
            ParkingViewport(
                south: viewport.south + offset,
                west: viewport.west + offset,
                north: viewport.north + offset,
                east: viewport.east + offset,
                zoomLevel: viewport.zoomLevel
            )
        }
        let first = moved(0)
        let second = moved(0.01)
        let third = moved(0.02)

        _ = try await repository.refresh(viewport: first, proximityReference: reference(), plan: plan(.oneHour), now: now)
        _ = try await repository.refresh(viewport: second, proximityReference: reference(), plan: plan(.oneHour), now: now)
        _ = try await repository.refresh(viewport: first, proximityReference: reference(), plan: plan(.oneHour), now: now)
        _ = try await repository.refresh(viewport: third, proximityReference: reference(), plan: plan(.oneHour), now: now)
        _ = try await repository.refresh(viewport: second, proximityReference: reference(), plan: plan(.oneHour), now: now)

        let fetchCount = await api.fetchCount
        XCTAssertEqual(fetchCount, 4, "Reading the first viewport should keep it newer than the second viewport")
    }

    func testSuggestionRequiresARealComparisonSet() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7001, status: .unoccupied, bayCount: 5, newestTimestamp: now),
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7001, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P"),
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.oneHour), now: now, force: true
        )

        XCTAssertEqual(result.zones.count, 2)
        XCTAssertEqual(result.zones.filter(\.isSuggested).count, 1)
        XCTAssertEqual(
            result.zones.first(where: \.isSuggested)?.recommendationExplanation,
            "We compare street parking found in this map area. Expected available spaces matter most, followed by straight-line distance to Test destination, then the chance of finding a space."
        )
    }

    func testAllZeroLiveCountsAreNotSuggested() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7001, status: .present, bayCount: 6, newestTimestamp: now),
            .init(zoneNumber: 7002, status: .present, bayCount: 5, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7001, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P"),
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.oneHour), now: now, force: true
        )

        XCTAssertEqual(result.zones.count, 2)
        XCTAssertEqual(result.zones.filter(\.isSuggested).count, 0)
        XCTAssertTrue(result.zones.allSatisfy { $0.recommendationExplanation == nil })
    }

    func testRefreshCacheAndDistanceUseTheStableDestinationReference() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], cacheTTL: 120)
        let firstReference = reference(coordinate: .melbourneCBD, label: "First destination")
        let secondReference = reference(
            coordinate: .init(latitude: -37.800, longitude: 144.940),
            label: "Second destination"
        )

        let first = try await repository.refresh(
            viewport: viewport, proximityReference: firstReference,
            plan: plan(.oneHour), now: now
        )
        let second = try await repository.refresh(
            viewport: viewport, proximityReference: secondReference,
            plan: plan(.oneHour), now: now.addingTimeInterval(1)
        )

        let fetchCount = await api.fetchCount
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(first.zones.first?.proximity.reference, firstReference)
        XCTAssertEqual(second.zones.first?.proximity.reference, secondReference)
        XCTAssertNotEqual(
            first.zones.first?.proximity.straightLineMetres,
            second.zones.first?.proximity.straightLineMetres
        )
    }

    func testCacheDoesNotReuseProximityWhenOnlyTheDestinationLabelChanges() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], cacheTTL: 120)

        let first = try await repository.refresh(
            viewport: viewport, proximityReference: reference(label: "First name"),
            plan: plan(.oneHour), now: now
        )
        let second = try await repository.refresh(
            viewport: viewport, proximityReference: reference(label: "Second name"),
            plan: plan(.oneHour), now: now.addingTimeInterval(1)
        )

        let fetchCount = await api.fetchCount
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(first.zones.first?.proximity.reference.label, "First name")
        XCTAssertEqual(second.zones.first?.proximity.reference.label, "Second name")
    }

    func testNetworkFailureReturnsTypicalHistoryWithoutCallingItLive() async throws {
        let api = FixtureParkingAPI(rows: [], failure: ParkingAPIError.httpStatus(503))
        let history = [HistoricalBucket(segmentKey: metadata[1].segmentKey, weekday: 5, interval: 40, occupiedRatio: 0.4, turnover: 0.3, sampleCount: 800)]
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], historyLoader: { history }, forecastValidationBySegment: [
            metadata[1].segmentKey: .init(
                sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
                intervalCoverage: 0.9, observedThrough: now.addingTimeInterval(-86_400),
                modelVersion: "fixture-v2"
            )
        ])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.oneHour), now: now, force: true
        )

        XCTAssertEqual(result.mode, .typical)
        XCTAssertNil(result.checkedAt)
        XCTAssertFalse(result.zones.isEmpty)
        XCTAssertTrue(result.notice.contains("Typical"))
    }

    func testThreeHourFilterExcludesShorterTimeLimits() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7001, status: .unoccupied, bayCount: 5, newestTimestamp: now),
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7001, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "MP2P"),
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "MP3P")
        ], history: [])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.threeHours), now: now, force: true
        )

        XCTAssertEqual(result.zones.map(\.zoneNumber), [7002])
        XCTAssertEqual(result.zones.first?.restrictionLabel, "Up to 3 hours, meter required")
    }

    func testNoEligibleOnStreetZoneIsAValidFilteredResultNotANetworkError() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7001, status: .unoccupied, bayCount: 5, newestTimestamp: now)
        ])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7001, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "1P")
        ], history: [])

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: plan(.threeHours), now: now, force: true
        )

        XCTAssertEqual(result.mode, .live)
        XCTAssertTrue(result.zones.isEmpty)
        XCTAssertTrue(result.notice.contains(StayDuration.threeHours.selectionDescription))
        XCTAssertTrue(result.notice.contains("off-street"))
        XCTAssertFalse(result.notice.localizedCaseInsensitiveContains("connection"))
    }

    func testHistoricalFallbackNeverSubstitutesANearbyOccupiedBucketForMissingTime() async {
        let api = FixtureParkingAPI(rows: [], failure: ParkingAPIError.httpStatus(503))
        let history = [
            HistoricalBucket(
                segmentKey: metadata[1].segmentKey, weekday: 5, interval: 39,
                occupiedRatio: 0.95, turnover: 0.2, sampleCount: 2_000,
                observationState: .observedOccupied, observedThrough: now.addingTimeInterval(-86_400)
            )
        ]
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
            intervalCoverage: 0.9, observedThrough: now.addingTimeInterval(-86_400),
            modelVersion: "fixture-v2"
        )
        let repository = ParkingRepository(
            api: api, metadata: metadata,
            restrictions: [.init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")],
            history: history, forecastValidationBySegment: [metadata[1].segmentKey: validation]
        )

        do {
            _ = try await repository.refresh(
                viewport: viewport, proximityReference: reference(),
                plan: plan(.oneHour), now: now, force: true
            )
            XCTFail("A missing 10:00 bucket must abstain instead of borrowing the 9:45 bucket")
        } catch {
            XCTAssertEqual(error as? ParkingAPIError, .invalidResponse)
        }
    }

    func testFuturePlanWithoutNumericForecastDoesNotReuseLiveCountForSuggestion() async throws {
        let api = FixtureParkingAPI(rows: [
            .init(zoneNumber: 7002, status: .unoccupied, bayCount: 4, newestTimestamp: now)
        ])
        let repository = ParkingRepository(
            api: api,
            metadata: metadata,
            restrictions: [
                .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
            ],
            history: []
        )
        let futurePlan = ParkingPlan(arrival: now.addingTimeInterval(60 * 60), duration: .oneHour)

        let result = try await repository.refresh(
            viewport: viewport, proximityReference: reference(),
            plan: futurePlan, now: now, force: true
        )

        XCTAssertEqual(result.mode, .live)
        XCTAssertEqual(result.zones.count, 1)
        XCTAssertEqual(result.zones.first?.prediction.abstentionReason, .missingHistory)
        XCTAssertFalse(result.zones.first?.isSuggested == true)
        XCTAssertTrue(result.notice.localizedCaseInsensitiveContains("not a forecast"))
    }

    private var metadata: [ZoneMetadata] {
        [
            .init(zoneNumber: 7001, streetName: "Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: -37.815, longitude: 144.965), sensorCount: 6),
            .init(zoneNumber: 7002, streetName: "Little Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: -37.814, longitude: 144.964), sensorCount: 5)
        ]
    }

    private func plan(_ duration: StayDuration) -> ParkingPlan {
        ParkingPlan(arrival: now, duration: duration)
    }

    private func reference(
        coordinate: Coordinate = .melbourneCBD,
        label: String = "Test destination"
    ) -> ParkingProximityReference {
        .init(coordinate: coordinate, label: label)
    }

    private var viewport: ParkingViewport {
        .init(south: -37.83, west: 144.94, north: -37.79, east: 144.99, zoomLevel: 14)
    }
}

actor FixtureParkingAPI: ParkingAPIProviding {
    private let rows: [SensorAggregateRow]
    private let failure: Error?
    private(set) var fetchCount = 0

    init(rows: [SensorAggregateRow], failure: Error? = nil) {
        self.rows = rows
        self.failure = failure
    }

    func fetchZoneCounts(near: Coordinate, radiusMetres: Int, since: Date) async throws -> [SensorAggregateRow] {
        fetchCount += 1
        if let failure { throw failure }
        return rows
    }

    func fetchVacantBays(zoneNumber: Int, since: Date) async throws -> [SensorReading] { [] }
}

private actor CancellableParkingAPI: ParkingAPIProviding {
    private var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func fetchZoneCounts(near: Coordinate, radiusMetres: Int, since: Date) async throws -> [SensorAggregateRow] {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: .seconds(30))
        return []
    }

    func fetchVacantBays(zoneNumber: Int, since: Date) async throws -> [SensorReading] { [] }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }
}

private final class SynchronousCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

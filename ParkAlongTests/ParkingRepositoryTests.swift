import XCTest
@testable import ParkAlong

final class ParkingRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_776_297_600) // Thursday 10am in Melbourne

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

        let result = try await repository.refresh(destination: .melbourneCBD, duration: .twoHours, now: now, force: true)

        XCTAssertEqual(result.mode, .live)
        XCTAssertEqual(result.zones.map(\.zoneNumber), [7002])
        XCTAssertEqual(result.zones.first?.available, 2)
        XCTAssertEqual(result.zones.first?.payment, .paid)
        XCTAssertTrue(result.zones.first?.isBestBet == true)
    }

    func testRefreshUsesShortCacheButExpiresAtTwoMinutes() async throws {
        let api = FixtureParkingAPI(rows: [.init(zoneNumber: 7002, status: .unoccupied, bayCount: 2, newestTimestamp: now)])
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], cacheTTL: 120)

        _ = try await repository.refresh(destination: .melbourneCBD, duration: .oneHour, now: now)
        _ = try await repository.refresh(destination: .melbourneCBD, duration: .oneHour, now: now.addingTimeInterval(119))
        let countBeforeExpiry = await api.fetchCount
        XCTAssertEqual(countBeforeExpiry, 1)
        _ = try await repository.refresh(destination: .melbourneCBD, duration: .oneHour, now: now.addingTimeInterval(120))
        let countAfterExpiry = await api.fetchCount
        XCTAssertEqual(countAfterExpiry, 2)
    }

    func testNetworkFailureReturnsTypicalHistoryWithoutCallingItLive() async throws {
        let api = FixtureParkingAPI(rows: [], failure: ParkingAPIError.httpStatus(503))
        let history = [HistoricalBucket(segmentKey: metadata[1].segmentKey, weekday: 5, interval: 40, occupiedRatio: 0.4, turnover: 0.3, sampleCount: 800)]
        let repository = ParkingRepository(api: api, metadata: metadata, restrictions: [
            .init(zoneNumber: 7002, days: "Mon-Sun", start: "00:00:00", finish: "23:59:59", display: "3P")
        ], history: [], historyLoader: { history })

        let result = try await repository.refresh(destination: .melbourneCBD, duration: .oneHour, now: now, force: true)

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

        let result = try await repository.refresh(destination: .melbourneCBD, duration: .threePlusHours, now: now, force: true)

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

        let result = try await repository.refresh(destination: .melbourneCBD, duration: .threePlusHours, now: now, force: true)

        XCTAssertEqual(result.mode, .live)
        XCTAssertTrue(result.zones.isEmpty)
        XCTAssertTrue(result.notice.contains(StayDuration.threePlusHours.selectionDescription))
        XCTAssertTrue(result.notice.contains("off-street"))
        XCTAssertFalse(result.notice.localizedCaseInsensitiveContains("connection"))
    }

    private var metadata: [ZoneMetadata] {
        [
            .init(zoneNumber: 7001, streetName: "Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: -37.815, longitude: 144.965), sensorCount: 6),
            .init(zoneNumber: 7002, streetName: "Little Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: -37.814, longitude: 144.964), sensorCount: 5)
        ]
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

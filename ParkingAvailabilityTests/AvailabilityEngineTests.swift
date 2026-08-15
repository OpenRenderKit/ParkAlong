import XCTest
@testable import ParkingAvailability

final class AvailabilityEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGroupingCountsOnlyRecognisedFreshSensorsWithZones() {
        let rows = [
            SensorReading(kerbsideID: 1, zoneNumber: 7001, status: .unoccupied, timestamp: now.addingTimeInterval(-60), coordinate: .init(latitude: -37.81, longitude: 144.96)),
            SensorReading(kerbsideID: 2, zoneNumber: 7001, status: .present, timestamp: now.addingTimeInterval(-90), coordinate: .init(latitude: -37.82, longitude: 144.97)),
            SensorReading(kerbsideID: 3, zoneNumber: 7001, status: .unoccupied, timestamp: now.addingTimeInterval(-86_401), coordinate: .init(latitude: -37.82, longitude: 144.97)),
            SensorReading(kerbsideID: 4, zoneNumber: nil, status: .unoccupied, timestamp: now, coordinate: .init(latitude: -37.82, longitude: 144.97)),
            SensorReading(kerbsideID: 5, zoneNumber: 7001, status: .unknown, timestamp: now, coordinate: .init(latitude: -37.82, longitude: 144.97))
        ]

        let grouped = AvailabilityEngine.group(readings: rows, now: now)

        XCTAssertEqual(grouped[7001]?.available, 1)
        XCTAssertEqual(grouped[7001]?.total, 2)
        XCTAssertEqual(grouped[7001]?.newestTimestamp, now.addingTimeInterval(-60))
    }

    func testAggregateGroupingRejectsBroadlyStaleRows() {
        let rows = [
            SensorAggregateRow(zoneNumber: 7001, status: .unoccupied, bayCount: 4, newestTimestamp: now.addingTimeInterval(-86_401)),
            SensorAggregateRow(zoneNumber: 7002, status: .present, bayCount: 2, newestTimestamp: now.addingTimeInterval(-30))
        ]

        let grouped = AvailabilityEngine.group(aggregates: rows, now: now)

        XCTAssertNil(grouped[7001])
        XCTAssertEqual(grouped[7002]?.total, 2)
    }

    func testBoundaryAtExactlyTwentyFourHoursIsTrusted() {
        let row = SensorReading(kerbsideID: 1, zoneNumber: 7001, status: .unoccupied, timestamp: now.addingTimeInterval(-86_400), coordinate: .init(latitude: -37.81, longitude: 144.96))
        XCTAssertEqual(AvailabilityEngine.group(readings: [row], now: now)[7001]?.available, 1)
    }
}


import XCTest
@testable import ParkAlong

final class StaticParkingSpatialIndexTests: XCTestCase {
    func testQueryReturnsExactlyLocationsIntersectingViewportAcrossCellEdges() {
        let locations = [
            fixture(id: "south-west", latitude: -37.8201, longitude: 144.9499),
            fixture(id: "inside", latitude: -37.8100, longitude: 144.9600),
            fixture(id: "north-east", latitude: -37.7999, longitude: 144.9701),
            fixture(id: "outside-north", latitude: -37.7900, longitude: 144.9600),
            fixture(id: "outside-east", latitude: -37.8100, longitude: 145.0000),
        ]
        let index = StaticParkingSpatialIndex(locations: locations, cellSizeDegrees: 0.01)
        let viewport = ParkingViewport(
            south: -37.825, west: 144.945,
            north: -37.795, east: 144.975,
            zoomLevel: 14
        )

        let matches = index.locations(in: viewport)

        XCTAssertEqual(Set(matches.map(\.id)), ["south-west", "inside", "north-east"])
    }

    func testQueryDoesNotDuplicateLocationsWhenViewportCrossesManyCells() {
        let locations = (0..<50).map { index in
            fixture(
                id: "location-\(index)",
                latitude: -37.90 + Double(index % 10) * 0.02,
                longitude: 144.85 + Double(index / 10) * 0.03
            )
        }
        let index = StaticParkingSpatialIndex(locations: locations, cellSizeDegrees: 0.01)
        let viewport = ParkingViewport(
            south: -38.0, west: 144.7,
            north: -37.6, east: 145.1,
            zoomLevel: 10
        )

        let matches = index.locations(in: viewport)

        XCTAssertEqual(matches.count, locations.count)
        XCTAssertEqual(Set(matches.map(\.id)).count, locations.count)
    }

    func testQueryChecksOnlyIntersectingCellsForAStreetScaleViewport() {
        let locations = (0..<1_000).map { index in
            fixture(
                id: "statewide-\(index)",
                latitude: -39.0 + Double(index / 40) * 0.2,
                longitude: 141.0 + Double(index % 40) * 0.2
            )
        } + [fixture(id: "target", latitude: -37.8136, longitude: 144.9631)]
        let index = StaticParkingSpatialIndex(locations: locations, cellSizeDegrees: 0.02)
        let viewport = ParkingViewport(
            south: -37.82, west: 144.95,
            north: -37.80, east: 144.98,
            zoomLevel: 14
        )

        let result = index.query(in: viewport)

        XCTAssertEqual(result.locations.map(\.id), ["target"])
        XCTAssertLessThan(result.inspectedLocationCount, locations.count / 20)
    }

    private func fixture(id: String, latitude: Double, longitude: Double) -> StaticParkingLocation {
        StaticParkingLocation(
            id: id,
            name: id,
            municipality: "Fixture",
            coordinate: .init(latitude: latitude, longitude: longitude),
            kind: .offStreet,
            archetype: .general,
            capacity: nil,
            accessibleSpaces: nil,
            schedules: [],
            tariffs: [],
            source: .init(
                id: "fixture",
                name: "Fixture",
                sourceURL: URL(string: "https://example.com")!,
                licenseName: "Fixture",
                licenseURL: nil,
                datasetUpdatedAt: nil,
                checkedAt: Date(timeIntervalSince1970: 1_777_000_000)
            ),
            classification: .staticOnly,
            predictionEvidence: nil
        )
    }
}

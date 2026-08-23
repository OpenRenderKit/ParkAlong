import XCTest
@testable import ParkAlong

final class DestinationSearchServiceTests: XCTestCase {
    func testParkingAwareRankingKeepsTextRelevanceAheadOfParkingBoost() {
        let viewport = ParkingViewport(south: -38, west: 144, north: -37, east: 145, zoomLevel: 12)
        let exactPlace = ParkingDestination(
            id: "place", name: "Royal Melbourne Hospital", subtitle: "Parkville",
            coordinate: .init(latitude: -37.8, longitude: 144.95)
        )
        let weakParking = ParkingDestination(
            id: "parking", name: "Royal Parade parking", subtitle: "Parkville",
            coordinate: .init(latitude: -37.8, longitude: 144.95), kind: .parking,
            parkingOptionID: "static-1"
        )

        let ranked = DestinationSearchRanker.rank(
            [weakParking, exactPlace], query: "Royal Melbourne Hospital", viewport: viewport
        )

        XCTAssertEqual(ranked.map(\.id), ["place", "parking"])
    }

    func testParkingResultWinsWhenItIsTheExactUserIntent() {
        let viewport = ParkingViewport(south: -38, west: 144, north: -37, east: 145, zoomLevel: 12)
        let place = ParkingDestination(
            id: "place", name: "Queen Victoria Market", subtitle: "Melbourne",
            coordinate: .melbourneCBD
        )
        let parking = ParkingDestination(
            id: "parking", name: "Queen Victoria Market parking", subtitle: "Official car park",
            coordinate: .melbourneCBD, kind: .parking, parkingOptionID: "static-1"
        )

        let ranked = DestinationSearchRanker.rank(
            [place, parking], query: "Queen Victoria Market parking", viewport: viewport
        )

        XCTAssertEqual(ranked.first?.id, "parking")
    }
}

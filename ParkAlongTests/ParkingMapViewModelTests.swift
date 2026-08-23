import XCTest
@testable import ParkAlong

@MainActor
final class ParkingMapViewModelTests: XCTestCase {
    func testRefreshLoadsStaticCatalogAlongsideLiveAndMapKitResults() async {
        let now = Date()
        let location = StaticParkingLocation(
            id: "regional", name: "Regional car park", municipality: "Regional Victoria",
            coordinate: .melbourneCBD, kind: .offStreet, archetype: .general, capacity: 50, accessibleSpaces: 2,
            schedules: [], tariffs: [],
            source: .init(id: "official", name: "Regional Council", sourceURL: URL(string: "https://example.com")!,
                          licenseName: "Official", licenseURL: nil, datasetUpdatedAt: now, checkedAt: now),
            classification: .staticOnly, predictionEvidence: nil
        )
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(),
            staticParkingService: StaticParkingRepository(locations: [location])
        )

        await viewModel.refresh(force: true)

        XCTAssertFalse(viewModel.zones.isEmpty)
        XCTAssertFalse(viewModel.offStreetOptions.isEmpty)
        XCTAssertEqual(viewModel.staticOptions.map(\.title), ["Regional car park"])
        XCTAssertEqual(viewModel.staticOptions.first?.classification, .staticOnly)
    }
}

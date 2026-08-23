import XCTest
@testable import ParkAlong

@MainActor
final class ParkingMapViewModelTests: XCTestCase {
    func testChoosingDestinationRefreshesOneMapSizedViewport() async {
        let repository = RefreshCountingParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let destination = ParkingDestination(
            id: "bendigo", name: "Bendigo", subtitle: "Victoria",
            coordinate: .init(latitude: -36.757, longitude: 144.279)
        )

        await viewModel.chooseDestination(destination)

        let refreshCount = await repository.refreshCount
        let lastViewport = await repository.lastViewport
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(lastViewport, viewModel.viewport)
        XCTAssertLessThan(viewModel.viewport.latitudeSpan, 0.01)
        XCTAssertLessThan(viewModel.viewport.longitudeSpan, 0.015)
        XCTAssertEqual(viewModel.mapFocusRequest, viewModel.viewport)
    }

    func testSelectingDurationUpdatesTheVisibleChoiceImmediately() {
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        viewModel.selectDuration(.twoHours)

        XCTAssertEqual(viewModel.duration, .twoHours)
    }

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

    func testRefreshPassesTheExactVisibleViewportToOffStreetDiscovery() async {
        let offStreet = ViewportCapturingOffStreetService()
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: offStreet,
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let bendigoViewport = ParkingViewport(
            south: -36.80, west: 144.20, north: -36.70, east: 144.36, zoomLevel: 12
        )
        viewModel.viewport = bendigoViewport

        await viewModel.refresh(force: true)

        let requestedViewport = await offStreet.lastViewport
        XCTAssertEqual(requestedViewport, bendigoViewport)
    }

    func testSelectingClusterRequestsZoomInsteadOfOpeningParkingDetails() async {
        let now = Date()
        let locations = (0..<5).map { index in
            StaticParkingLocation(
                id: "cluster-\(index)", name: "Parking \(index)", municipality: "Fixture",
                coordinate: .init(latitude: -37.81 + Double(index) * 0.00005, longitude: 144.96),
                kind: .offStreet, archetype: .general, capacity: 20, accessibleSpaces: nil,
                schedules: [], tariffs: [],
                source: .init(id: "official", name: "Fixture Council", sourceURL: URL(string: "https://example.com")!,
                              licenseName: "Official", licenseURL: nil, datasetUpdatedAt: now, checkedAt: now),
                classification: .staticOnly, predictionEvidence: nil
            )
        }
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live), locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(), navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: locations)
        )
        viewModel.viewport = ParkingViewport(south: -38.0, west: 144.7, north: -37.6, east: 145.1, zoomLevel: 9)
        await viewModel.refresh(force: true)
        let cluster = try! XCTUnwrap(viewModel.staticOptions.first)

        viewModel.selectStatic(cluster)

        XCTAssertNil(viewModel.selectedOffStreetOption)
        XCTAssertEqual(viewModel.mapFocusRequest, cluster.clusterViewport)
        XCTAssertEqual(viewModel.viewport, cluster.clusterViewport)
    }
}

private actor RefreshCountingParkingRepository: ParkingRepositoryProviding {
    private(set) var refreshCount = 0
    private(set) var lastViewport: ParkingViewport?

    func refresh(
        viewport: ParkingViewport,
        plan: ParkingPlan,
        now: Date,
        force: Bool
    ) async throws -> ParkingRepositoryResult {
        refreshCount += 1
        lastViewport = viewport
        return .init(zones: [], mode: .typical, checkedAt: now, notice: "")
    }

    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate] { [] }
}

private actor ViewportCapturingOffStreetService: OffStreetParkingProviding {
    private(set) var lastViewport: ParkingViewport?

    func options(in viewport: ParkingViewport) async -> [ParkingOption] {
        lastViewport = viewport
        return []
    }
}

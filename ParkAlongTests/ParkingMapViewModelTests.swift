import CoreLocation
import XCTest
@testable import ParkAlong

@MainActor
final class ParkingMapViewModelTests: XCTestCase {
    func testStartCentersOnAuthorizedCurrentLocationBeforeFirstRefresh() async {
        let current = Coordinate(latitude: -37.736, longitude: 145.001)
        let repository = RefreshCountingParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: ImmediateLocationService(coordinate: current),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.destination.id, "current")
        XCTAssertEqual(viewModel.viewport.center.latitude, current.latitude, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.viewport.center.longitude, current.longitude, accuracy: 0.000_001)
        let lastViewport = await repository.lastViewport
        XCTAssertEqual(lastViewport?.center, viewModel.viewport.center)
    }

    func testStartingTwiceDoesNotSnapBackToLocationOrRequestItAgain() async {
        let current = Coordinate(latitude: -37.736, longitude: 145.001)
        let location = ImmediateLocationService(coordinate: current)
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        await viewModel.start()
        let userViewport = ParkingViewport(
            south: -36.82, west: 144.20,
            north: -36.70, east: 144.36,
            zoomLevel: 12
        )
        viewModel.viewport = userViewport

        await viewModel.start()

        XCTAssertEqual(viewModel.viewport, userViewport)
        XCTAssertEqual(location.requestCount, 1)
    }

    func testUserMapInteractionWinsOverDelayedStartupLocation() async {
        let location = ControllableLocationService()
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let start = Task { await viewModel.start() }
        await location.waitUntilRequested()
        let userViewport = ParkingViewport(
            south: -36.82, west: 144.20,
            north: -36.70, east: 144.36,
            zoomLevel: 12
        )

        viewModel.updateViewport(userViewport, interactionEnded: false, userInitiated: true)
        await start.value

        XCTAssertEqual(viewModel.destination.id, "map-area")
        XCTAssertEqual(viewModel.destination.coordinate, userViewport.center)
        XCTAssertEqual(viewModel.viewport, userViewport)
        XCTAssertNil(viewModel.mapFocusRequest)
        XCTAssertEqual(location.cancellationCount, 1)
    }

    func testAutomaticCameraSettleDoesNotRefreshWhileStartupLocationIsPending() async {
        let location = ControllableLocationService()
        let repository = RefreshCountingParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: []),
            viewportDebounce: .zero
        )
        let originalViewport = viewModel.viewport
        let start = Task { await viewModel.start() }
        await location.waitUntilRequested()
        let automaticViewport = ParkingViewport(
            south: -44, west: 141,
            north: -34, east: 151,
            zoomLevel: 5
        )

        viewModel.updateViewport(automaticViewport, interactionEnded: true, userInitiated: false)
        await Task.yield()

        let refreshCount = await repository.refreshCount
        XCTAssertEqual(viewModel.viewport, originalViewport)
        XCTAssertEqual(refreshCount, 0)
        start.cancel()
        await start.value
    }

    func testSceneActivationDoesNotRefreshWhileStartupLocationIsPending() async {
        let location = ControllableLocationService()
        let repository = RefreshCountingParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let start = Task { await viewModel.start() }
        await location.waitUntilRequested()

        await viewModel.refreshAfterActivation()

        let refreshCount = await repository.refreshCount
        XCTAssertEqual(refreshCount, 0)
        start.cancel()
        await start.value
    }

    func testCancelledStartupCanRestartWhenMapReappears() async {
        let location = ControllableLocationService()
        let current = Coordinate(latitude: -37.736, longitude: 145.001)
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let firstStart = Task { await viewModel.start() }
        await location.waitUntilRequested()

        viewModel.cancelOutstandingWork()
        await firstStart.value
        let secondStart = Task { await viewModel.start() }
        await location.waitUntilRequested()
        location.complete(.success(current))
        await secondStart.value

        XCTAssertEqual(location.requestCount, 2)
        XCTAssertEqual(viewModel.destination.id, "current")
        XCTAssertEqual(viewModel.viewport.center, current)
    }

    func testDeniedStartupUsesClearMelbourneFallback() async {
        let repository = RefreshCountingParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: ResultLocationService(result: .denied),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.destination.id, "cbd")
        XCTAssertEqual(viewModel.destination.subtitle, "Location permission denied")
        XCTAssertTrue(viewModel.notice.localizedCaseInsensitiveContains("Melbourne CBD"))
        let requestedViewport = await repository.lastViewport
        XCTAssertEqual(requestedViewport?.center, Coordinate.melbourneCBD)
    }

    func testRestrictedStartupUsesClearMelbourneFallback() async {
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: ResultLocationService(result: .restricted),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.destination.subtitle, "Location access restricted")
        XCTAssertEqual(viewModel.viewport.center, Coordinate.melbourneCBD)
    }

    func testLocationTimeoutFallsBackWithoutHanging() async {
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: ResultLocationService(result: .timedOut),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        await viewModel.start()

        XCTAssertEqual(viewModel.destination.subtitle, "Current location timed out")
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testUnavailableSimulatorLocationFallsBackWithoutRepeatedSnapping() async {
        let location = ResultLocationService(result: .unavailable)
        let viewModel = ParkingMapViewModel(
            repository: FixtureParkingRepository(mode: .live),
            locationService: location,
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )

        await viewModel.start()
        let userViewport = ParkingViewport(south: -38.2, west: 144.2, north: -38.0, east: 144.4, zoomLevel: 12)
        viewModel.viewport = userViewport
        await viewModel.start()

        XCTAssertEqual(viewModel.destination.subtitle, "Current location unavailable")
        XCTAssertEqual(viewModel.viewport, userViewport)
        XCTAssertEqual(location.requestCount, 1)
    }

    func testNewRefreshCancelsInFlightRefreshAndOnlyAppliesNewestResult() async {
        let repository = ControllableParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let firstViewport = ParkingViewport(south: -37.84, west: 144.92, north: -37.78, east: 145.00, zoomLevel: 14)
        let secondViewport = ParkingViewport(south: -36.82, west: 144.20, north: -36.70, east: 144.36, zoomLevel: 12)

        viewModel.viewport = firstViewport
        let firstRefresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(1)
        viewModel.viewport = secondViewport
        let secondRefresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(2)
        await repository.completeLast(with: result(notice: "newest"))
        await secondRefresh.value

        let cancellationCount = await repository.cancelledRequestCount
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(viewModel.notice, "newest")
        firstRefresh.cancel()
        await firstRefresh.value
    }

    func testCancellingRefreshCallerCancelsOwnedRepositoryWork() async {
        let repository = ControllableParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: [])
        )
        let refresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(1)

        refresh.cancel()
        await repository.waitForCancellationCount(1)
        await refresh.value

        let cancellationCount = await repository.cancelledRequestCount
        XCTAssertEqual(cancellationCount, 1)
    }

    func testRefreshKeepsPreviouslyVisibleMarkersWhileNewDataIsLoading() async {
        let repository = ControllableParkingRepository()
        let staticService = ControllableStaticParkingService()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: staticService
        )
        let existing = makeStaticOption(id: "existing")
        viewModel.staticOptions = [existing]

        let refresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(1)

        XCTAssertEqual(viewModel.staticOptions.map(\.id), ["existing"])
        XCTAssertEqual(viewModel.state, .loading)

        await repository.completeLast(with: result(notice: "loaded"))
        await staticService.completeLast(with: [])
        await refresh.value
    }

    func testRefreshRebindsSelectedStaticDetailsToFreshOption() async {
        let repository = ControllableParkingRepository()
        let staticService = ControllableStaticParkingService()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: staticService
        )
        let old = makeStaticOption(id: "selected")
        var updated = makeStaticOption(id: "selected")
        updated = ParkingOption(
            id: updated.id, kind: updated.kind, title: "Fresh details", locationLabel: updated.locationLabel,
            coordinate: updated.coordinate, availabilityState: updated.availabilityState,
            available: updated.available, total: updated.total, restrictionLabel: updated.restrictionLabel,
            restrictionWindow: updated.restrictionWindow, activeNow: updated.activeNow, price: updated.price,
            provider: updated.provider, sourceTimestamp: updated.sourceTimestamp, walkingMetres: updated.walkingMetres,
            prediction: updated.prediction, isBestBet: updated.isBestBet, zoneNumber: updated.zoneNumber,
            classification: updated.classification, warningText: updated.warningText,
            sourceDatasetAt: updated.sourceDatasetAt, sourceCheckedAt: updated.sourceCheckedAt,
            schedule: updated.schedule, clusterCount: updated.clusterCount, clusterViewport: updated.clusterViewport
        )
        viewModel.selectedOffStreetOption = old
        let refresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(1)

        await repository.completeLast(with: result(notice: "fresh"))
        await staticService.completeLast(with: [updated])
        await refresh.value

        XCTAssertEqual(viewModel.selectedOffStreetOption?.title, "Fresh details")
    }

    func testPartialFailureStillRebindsSelectedStaticDetails() async {
        let repository = ControllableParkingRepository()
        let staticService = ControllableStaticParkingService()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: staticService
        )
        let old = makeStaticOption(id: "selected")
        let updated = ParkingOption(
            id: old.id, kind: old.kind, title: "Fresh fallback details", locationLabel: old.locationLabel,
            coordinate: old.coordinate, availabilityState: old.availabilityState, available: old.available,
            total: old.total, restrictionLabel: old.restrictionLabel, restrictionWindow: old.restrictionWindow,
            activeNow: old.activeNow, price: old.price, provider: old.provider,
            sourceTimestamp: old.sourceTimestamp, walkingMetres: old.walkingMetres, prediction: old.prediction,
            isBestBet: old.isBestBet, zoneNumber: old.zoneNumber, classification: old.classification,
            warningText: old.warningText, sourceDatasetAt: old.sourceDatasetAt,
            sourceCheckedAt: old.sourceCheckedAt, schedule: old.schedule,
            clusterCount: old.clusterCount, clusterViewport: old.clusterViewport
        )
        viewModel.selectedOffStreetOption = old
        let refresh = Task { await viewModel.refresh(force: false) }
        await repository.waitForStartedRequestCount(1)

        await repository.failLast()
        await staticService.completeLast(with: [updated])
        await refresh.value

        XCTAssertEqual(viewModel.selectedOffStreetOption?.title, "Fresh fallback details")
        XCTAssertEqual(viewModel.state, .loaded)
    }

    func testRapidViewportUpdatesDebounceToOnlyTheNewestViewport() async {
        let repository = ControllableParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: []),
            viewportDebounce: .zero
        )
        let first = ParkingViewport(south: -37.9, west: 144.8, north: -37.7, east: 145.0, zoomLevel: 12)
        let newest = ParkingViewport(south: -36.82, west: 144.20, north: -36.70, east: 144.36, zoomLevel: 13)

        viewModel.updateViewport(first, interactionEnded: true)
        viewModel.updateViewport(newest, interactionEnded: true)
        await repository.waitForStartedRequestCount(1)

        let lastStartedViewport = await repository.lastStartedViewport
        let totalStartedCount = await repository.totalStartedCount
        XCTAssertEqual(lastStartedViewport!.south, -36.88, accuracy: 0.000_001)
        XCTAssertEqual(lastStartedViewport!.west, 144.12, accuracy: 0.000_001)
        XCTAssertEqual(lastStartedViewport!.north, -36.64, accuracy: 0.000_001)
        XCTAssertEqual(lastStartedViewport!.east, 144.44, accuracy: 0.000_001)
        XCTAssertEqual(lastStartedViewport!.zoomLevel, 13)
        XCTAssertEqual(totalStartedCount, 1)
        await repository.completeLast(with: result(notice: "newest"))
    }

    func testViewportRefreshQueriesBeyondEveryVisibleEdge() async {
        let repository = ControllableParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: []),
            viewportDebounce: .zero
        )
        let visible = ParkingViewport(
            south: -37.84, west: 144.92,
            north: -37.78, east: 145.00,
            zoomLevel: 14
        )

        viewModel.updateViewport(visible, interactionEnded: true)
        await repository.waitForStartedRequestCount(1)

        let queried = await repository.lastStartedViewport
        XCTAssertNotNil(queried)
        XCTAssertLessThan(queried!.south, visible.south)
        XCTAssertLessThan(queried!.west, visible.west)
        XCTAssertGreaterThan(queried!.north, visible.north)
        XCTAssertGreaterThan(queried!.east, visible.east)
        XCTAssertEqual(queried!.zoomLevel, visible.zoomLevel)
        await repository.completeLast(with: result(notice: "prefetched"))
    }

    func testImmaterialCameraJitterDoesNotStartAViewportRefresh() async {
        let repository = ControllableParkingRepository()
        let viewModel = ParkingMapViewModel(
            repository: repository,
            locationService: FixtureLocationService(denied: true),
            destinationSearch: FixtureDestinationSearchService(),
            navigator: AppleMapsNavigator(intercept: true),
            offStreetService: FixtureOffStreetParkingService(includeResult: false),
            staticParkingService: StaticParkingRepository(locations: []),
            viewportDebounce: .zero
        )
        let current = viewModel.viewport
        let jitter = ParkingViewport(
            south: current.south + current.latitudeSpan * 0.01,
            west: current.west + current.longitudeSpan * 0.01,
            north: current.north + current.latitudeSpan * 0.01,
            east: current.east + current.longitudeSpan * 0.01,
            zoomLevel: current.zoomLevel
        )

        viewModel.updateViewport(jitter, interactionEnded: true)
        await Task.yield()

        let totalStartedCount = await repository.totalStartedCount
        XCTAssertEqual(totalStartedCount, 0)
    }

    func testChoosingDestinationRefreshesOneBufferedMapViewport() async {
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
        XCTAssertLessThan(lastViewport!.south, viewModel.viewport.south)
        XCTAssertLessThan(lastViewport!.west, viewModel.viewport.west)
        XCTAssertGreaterThan(lastViewport!.north, viewModel.viewport.north)
        XCTAssertGreaterThan(lastViewport!.east, viewModel.viewport.east)
        XCTAssertEqual(lastViewport!.zoomLevel, viewModel.viewport.zoomLevel)
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

    func testRefreshPassesTheBufferedViewportToOffStreetDiscovery() async {
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
        XCTAssertEqual(requestedViewport!.south, -36.85, accuracy: 0.000_001)
        XCTAssertEqual(requestedViewport!.west, 144.12, accuracy: 0.000_001)
        XCTAssertEqual(requestedViewport!.north, -36.65, accuracy: 0.000_001)
        XCTAssertEqual(requestedViewport!.east, 144.44, accuracy: 0.000_001)
        XCTAssertEqual(requestedViewport!.zoomLevel, 12)
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

    private func result(notice: String) -> ParkingRepositoryResult {
        .init(zones: [], mode: .live, checkedAt: Date(timeIntervalSince1970: 1_777_000_000), notice: notice)
    }

    private func makeStaticOption(id: String) -> ParkingOption {
        .init(
            id: id, kind: .offStreet, title: id, locationLabel: "Fixture", coordinate: .melbourneCBD,
            availabilityState: .unknown, available: nil, total: nil,
            restrictionLabel: "Fixture", restrictionWindow: "Fixture", activeNow: true,
            price: .init(primaryText: "Fixture", detail: "Fixture", provider: "Fixture", actionLabel: nil, actionURL: nil),
            provider: "Fixture", sourceTimestamp: nil, walkingMetres: 0, prediction: nil,
            isBestBet: false, zoneNumber: nil, classification: .staticOnly,
            warningText: "Not live", sourceDatasetAt: nil, sourceCheckedAt: nil,
            schedule: [], clusterCount: nil, clusterViewport: nil
        )
    }
}

@MainActor
private final class ImmediateLocationService: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    let coordinate: Coordinate?
    private(set) var requestCount = 0

    init(coordinate: Coordinate?) {
        self.coordinate = coordinate
    }

    func requestCoordinate() async -> LocationRequestResult {
        requestCount += 1
        return coordinate.map(LocationRequestResult.success) ?? .unavailable
    }
}

@MainActor
private final class ResultLocationService: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus
    let result: LocationRequestResult
    private(set) var requestCount = 0

    init(result: LocationRequestResult) {
        self.result = result
        switch result {
        case .success: authorizationStatus = .authorizedWhenInUse
        case .denied: authorizationStatus = .denied
        case .restricted: authorizationStatus = .restricted
        case .timedOut, .unavailable, .cancelled: authorizationStatus = .authorizedWhenInUse
        }
    }

    func requestCoordinate() async -> LocationRequestResult {
        requestCount += 1
        return result
    }
}

@MainActor
private final class ControllableLocationService: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private var resultContinuation: CheckedContinuation<LocationRequestResult, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0

    func requestCoordinate() async -> LocationRequestResult {
        requestCount += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resultContinuation = continuation
                let waiters = requestWaiters
                requestWaiters.removeAll()
                waiters.forEach { $0.resume() }
                if Task.isCancelled {
                    finish(.cancelled)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                cancellationCount += 1
                finish(.cancelled)
            }
        }
    }

    func waitUntilRequested() async {
        guard resultContinuation == nil else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func complete(_ result: LocationRequestResult) {
        finish(result)
    }

    private func finish(_ result: LocationRequestResult) {
        let continuation = resultContinuation
        resultContinuation = nil
        continuation?.resume(returning: result)
    }
}

private actor ControllableParkingRepository: ParkingRepositoryProviding {
    private struct Pending {
        let id: Int
        let continuation: CheckedContinuation<ParkingRepositoryResult, Error>
    }

    private var nextID = 0
    private var totalStartedRequestCount = 0
    private var pending: [Pending] = []
    private var startedWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var cancelledRequestCount = 0
    private(set) var lastStartedViewport: ParkingViewport?

    var totalStartedCount: Int { totalStartedRequestCount }

    func refresh(viewport: ParkingViewport, plan: ParkingPlan, now: Date, force: Bool) async throws -> ParkingRepositoryResult {
        let id = nextID
        nextID += 1
        totalStartedRequestCount += 1
        lastStartedViewport = viewport
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Pending(id: id, continuation: continuation))
                resumeStartedWaiters()
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate] { [] }

    func waitForStartedRequestCount(_ count: Int) async {
        guard totalStartedRequestCount < count else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append((count, continuation))
        }
    }

    func waitForCancellationCount(_ count: Int) async {
        guard cancelledRequestCount < count else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append((count, continuation))
        }
    }

    func completeLast(with result: ParkingRepositoryResult) {
        guard let request = pending.popLast() else { return }
        request.continuation.resume(returning: result)
    }

    func failLast() {
        guard let request = pending.popLast() else { return }
        request.continuation.resume(throwing: URLError(.cannotConnectToHost))
    }

    private func cancel(id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let request = pending.remove(at: index)
        cancelledRequestCount += 1
        request.continuation.resume(throwing: CancellationError())
        let ready = cancellationWaiters.filter { cancelledRequestCount >= $0.count }
        cancellationWaiters.removeAll { cancelledRequestCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    private func resumeStartedWaiters() {
        let ready = startedWaiters.filter { totalStartedRequestCount >= $0.count }
        startedWaiters.removeAll { totalStartedRequestCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}

private actor ControllableStaticParkingService: StaticParkingProviding {
    private var pending: [CheckedContinuation<[ParkingOption], Never>] = []

    func options(in viewport: ParkingViewport, plan: ParkingPlan) async -> [ParkingOption] {
        await withCheckedContinuation { pending.append($0) }
    }

    func completeLast(with options: [ParkingOption]) {
        pending.popLast()?.resume(returning: options)
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

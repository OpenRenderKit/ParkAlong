import Foundation

@MainActor
enum AppEnvironment {
    static func makeViewModel(arguments: [String] = ProcessInfo.processInfo.arguments) -> ParkingMapViewModel {
        let isUITesting = arguments.contains("-ui-testing")
        let location = FixtureLocationService(denied: arguments.contains("-location-denied"))
        if isUITesting {
            let totalError = arguments.contains("-fixture-error")
            let repositoryError = totalError || arguments.contains("-fixture-live-error")
            let repository = FixtureParkingRepository(
                mode: repositoryError ? .error : (arguments.contains("-fixture-loading") ? .loading : .live)
            )
            return ParkingMapViewModel(
                repository: repository,
                locationService: location,
                destinationSearch: FixtureDestinationSearchService(),
                navigator: AppleMapsNavigator(intercept: arguments.contains("-intercept-navigation")),
                offStreetService: FixtureOffStreetParkingService(includeResult: !totalError),
                staticParkingService: FixtureStaticParkingService(includeResult: !totalError)
            )
        }

        do {
            let metadata = try BundleDataLoader.load([ZoneMetadata].self, named: "zone_metadata")
            let restrictions = try BundleDataLoader.load([RestrictionRecord].self, named: "restrictions")
            let repository = ParkingRepository(
                api: ParkingAPIClient(),
                metadata: metadata,
                restrictions: restrictions,
                history: [],
                historyLoader: { try BundleDataLoader.load([HistoricalBucket].self, named: "historical_availability") }
            )
            let staticParkingRepository = StaticParkingRepository(loader: {
                try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
            })
            return ParkingMapViewModel(repository: repository, locationService: LocationService(), destinationSearch: DestinationSearchService(), navigator: AppleMapsNavigator(), offStreetService: OffStreetParkingService(), staticParkingService: staticParkingRepository)
        } catch {
            return ParkingMapViewModel(repository: FixtureParkingRepository(mode: .error), locationService: LocationService(), destinationSearch: DestinationSearchService(), navigator: AppleMapsNavigator(), offStreetService: OffStreetParkingService(), staticParkingService: StaticParkingRepository(locations: []))
        }
    }
}

struct FixtureStaticParkingService: StaticParkingProviding {
    var includeResult = true

    func options(near destination: Coordinate, duration: StayDuration, at date: Date) async -> [ParkingOption] {
        guard includeResult else { return [] }
        let source = ParkingSourceAttribution(
            id: "fixture-static", name: "City of Ballarat",
            sourceURL: URL(string: "https://www.ballarat.vic.gov.au/city/parking/paying-parking-ballarat")!,
            licenseName: "Official council information", licenseURL: nil,
            datasetUpdatedAt: date.addingTimeInterval(-86_400), checkedAt: date
        )
        let location = StaticParkingLocation(
            id: "fixture-ballarat", name: "Sturt Street parking", municipality: "Ballarat",
            coordinate: .init(latitude: destination.latitude + 0.0012, longitude: destination.longitude - 0.0018),
            kind: .onStreet, archetype: .cbdRetail, capacity: 36, accessibleSpaces: nil,
            schedules: [.init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60, maxStayMinutes: nil,
                              restrictionText: "No signed maximum", appliesOnPublicHolidays: true, outsideWindowMeansUnrestricted: false)],
            tariffs: [.init(effectiveFrom: date.addingTimeInterval(-86_400), effectiveTo: nil, days: Array(1...7),
                            startMinutes: 0, endMinutes: 24 * 60, hourlyCents: 360, freeMinutes: 60,
                            dailyCapCents: nil, tiers: [])],
            source: source, classification: .staticOnly, predictionEvidence: nil
        )
        return await StaticParkingRepository(locations: [location]).options(near: destination, duration: duration, at: date)
    }
}

actor FixtureParkingRepository: ParkingRepositoryProviding {
    enum Mode { case live, loading, error }
    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    func refresh(destination: Coordinate, duration: StayDuration, now: Date, force: Bool) async throws -> ParkingRepositoryResult {
        if mode == .loading { try await Task.sleep(for: .seconds(30)) }
        if mode == .error { throw ParkingAPIError.httpStatus(503) }
        let metadata = [
            ZoneMetadata(zoneNumber: 7002, streetName: "Little Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: destination.latitude + 0.0015, longitude: destination.longitude + 0.0005), sensorCount: 7),
            ZoneMetadata(zoneNumber: 7311, streetName: "Russell Street", fromStreet: "Bourke Street", toStreet: "Little Collins Street", coordinate: .init(latitude: destination.latitude - 0.001, longitude: destination.longitude + 0.0018), sensorCount: 5),
            ZoneMetadata(zoneNumber: 7345, streetName: "Flinders Lane", fromStreet: "Russell Street", toStreet: "Exhibition Street", coordinate: .init(latitude: destination.latitude - 0.002, longitude: destination.longitude + 0.0025), sensorCount: 4)
        ]
        let available = [4, 2, 0]
        let zones = zip(metadata, available).enumerated().map { index, pair in
            let restrictionLabel: String
            switch duration {
            case .fifteenMinutes, .oneHour: restrictionLabel = "Up to 2 hours, meter required"
            case .twoHours: restrictionLabel = "Up to 3 hours, meter required"
            case .threeHours, .fourHours, .sixHours, .eightHours: restrictionLabel = "No timed limit right now"
            }
            return ParkingZone(
                zoneNumber: pair.0.zoneNumber,
                metadata: pair.0,
                available: pair.1,
                total: pair.0.sensorCount,
                restrictionLabel: restrictionLabel,
                payment: .paid,
                prediction: PredictionEngine.estimate(liveAvailable: pair.1, trustedBayCount: pair.0.sensorCount, historicalOccupiedRatio: 0.45, etaMinutes: 15, sampleCount: 700),
                walkingMetres: Double(170 + index * 110),
                newestTimestamp: now.addingTimeInterval(-Double(45 + index * 20)),
                mode: .live,
                isBestBet: index == 0
            )
        }
        return .init(zones: zones, mode: .live, checkedAt: now, notice: "\(duration.selectionDescription) stay · live availability · checked just now")
    }

    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate] {
        [.init(latitude: -37.8124, longitude: 144.9638), .init(latitude: -37.8126, longitude: 144.964)]
    }
}

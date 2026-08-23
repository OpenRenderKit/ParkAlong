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
            let validationRecords = (try? BundleDataLoader.load([ForecastValidationRecord].self, named: "historical_validation")) ?? []
            let repository = ParkingRepository(
                api: ParkingAPIClient(),
                metadata: metadata,
                restrictions: restrictions,
                history: [],
                historyLoader: { try BundleDataLoader.load([HistoricalBucket].self, named: "historical_availability") },
                forecastValidationBySegment: Dictionary(
                    validationRecords.map { ($0.segmentKey, $0.validation) },
                    uniquingKeysWith: { current, candidate in
                        candidate.observedThrough > current.observedThrough ? candidate : current
                    }
                )
            )
            let remote = RemoteParkingConfiguration.baseURL()
                .flatMap { try? RemoteParkingClient(baseURL: $0) }
            let catalogVersion = (try? BundleDataLoader.load(StaticCatalogManifest.self, named: "victoria_static_manifest"))?.version
                ?? "bundled-unversioned"
            let staticParkingRepository = StaticParkingRepository(
                loader: { try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking") },
                remote: remote,
                catalogVersion: catalogVersion
            )
            return ParkingMapViewModel(repository: repository, locationService: LocationService(), destinationSearch: DestinationSearchService(), navigator: AppleMapsNavigator(), offStreetService: OffStreetParkingService(), staticParkingService: staticParkingRepository)
        } catch {
            return ParkingMapViewModel(repository: FixtureParkingRepository(mode: .error), locationService: LocationService(), destinationSearch: DestinationSearchService(), navigator: AppleMapsNavigator(), offStreetService: OffStreetParkingService(), staticParkingService: StaticParkingRepository(locations: []))
        }
    }
}

struct FixtureStaticParkingService: StaticParkingProviding {
    var includeResult = true

    func options(in viewport: ParkingViewport, plan: ParkingPlan) async -> [ParkingOption] {
        guard includeResult else { return [] }
        let date = plan.arrival
        let destination = viewport.center
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
        return await StaticParkingRepository(locations: [location]).options(in: viewport, plan: plan)
    }
}

actor FixtureParkingRepository: ParkingRepositoryProviding {
    enum Mode { case live, loading, error }
    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    func refresh(viewport: ParkingViewport, plan: ParkingPlan, now: Date, force: Bool) async throws -> ParkingRepositoryResult {
        if mode == .loading { try await Task.sleep(for: .seconds(30)) }
        if mode == .error { throw ParkingAPIError.httpStatus(503) }
        let center = viewport.center
        let metadata = [
            ZoneMetadata(zoneNumber: 7002, streetName: "Little Collins Street", fromStreet: "Swanston Street", toStreet: "Russell Street", coordinate: .init(latitude: center.latitude + 0.0015, longitude: center.longitude + 0.0005), sensorCount: 7),
            ZoneMetadata(zoneNumber: 7311, streetName: "Russell Street", fromStreet: "Bourke Street", toStreet: "Little Collins Street", coordinate: .init(latitude: center.latitude - 0.001, longitude: center.longitude + 0.0018), sensorCount: 5),
            ZoneMetadata(zoneNumber: 7345, streetName: "Flinders Lane", fromStreet: "Russell Street", toStreet: "Exhibition Street", coordinate: .init(latitude: center.latitude - 0.002, longitude: center.longitude + 0.0025), sensorCount: 4)
        ]
        let available = [4, 2, 0]
        let zones = zip(metadata, available).enumerated().map { index, pair in
            let restrictionLabel: String
            switch plan.durationMinutes {
            case ...60: restrictionLabel = "Up to 2 hours, meter required"
            case ...120: restrictionLabel = "Up to 3 hours, meter required"
            default: restrictionLabel = "No timed limit right now"
            }
            return ParkingZone(
                zoneNumber: pair.0.zoneNumber,
                metadata: pair.0,
                available: pair.1,
                total: pair.0.sensorCount,
                restrictionLabel: restrictionLabel,
                payment: .paid,
                prediction: PredictionEngine.estimate(
                    liveAvailable: pair.1, trustedBayCount: pair.0.sensorCount,
                    historicalOccupiedRatio: 0.45, etaMinutes: 0,
                    validation: nil, forecastDate: now
                ),
                walkingMetres: Double(170 + index * 110),
                newestTimestamp: now.addingTimeInterval(-Double(45 + index * 20)),
                mode: .live,
                schedule: RestrictionEngine().weeklySchedule([
                    RestrictionRecord(
                        zoneNumber: pair.0.zoneNumber, days: "Mon-Sat", start: "07:00:00",
                        finish: "19:00:00", display: plan.durationMinutes <= 120 ? "MP2P" : "MP4P"
                    ),
                ], plan: plan),
                isBestBet: index == 0
            )
        }
        return .init(zones: zones, mode: .live, checkedAt: now, notice: "\(plan.selectionDescription) stay · live availability · checked just now")
    }

    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate] {
        [.init(latitude: -37.8124, longitude: 144.9638), .init(latitude: -37.8126, longitude: 144.964)]
    }
}

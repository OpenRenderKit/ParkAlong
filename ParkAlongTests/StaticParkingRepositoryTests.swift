import XCTest
@testable import ParkAlong

final class StaticParkingRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_000_000)

    func testGeneratedVictorianCatalogDecodesFromAppBundle() throws {
        let locations = try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
        XCTAssertEqual(locations.count, 30_890)
        XCTAssertEqual(Set(locations.map(\.source.id)).count, 11)
        XCTAssertTrue(locations.contains(where: { $0.source.id == "openstreetmap-victoria-parking" }))
        XCTAssertTrue(locations.contains(where: { $0.source.id == "maribyrnong-parking-explorer" }))
    }

    func testLazyLoaderSuppliesCatalogOffTheLaunchPath() async {
        let location = fixture(id: "lazy", name: "Lazy catalog", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(loader: { [location] })

        let options = await repository.options(near: .melbourneCBD, duration: .oneHour, at: now)

        XCTAssertEqual(options.map(\.title), ["Lazy catalog"])
    }

    func testReturnsNearbyStaticLocationWithResolvedRulePriceAndProvenance() async {
        let location = fixture(
            id: "ballarat-zone", name: "Sturt Street", coordinate: .init(latitude: -37.562, longitude: 143.858),
            schedules: [.init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60, maxStayMinutes: 180,
                              restrictionText: "3P", appliesOnPublicHolidays: true, outsideWindowMeansUnrestricted: false)],
            tariffs: [.init(effectiveFrom: now.addingTimeInterval(-86_400), effectiveTo: nil, days: Array(1...7),
                            startMinutes: 0, endMinutes: 24 * 60, hourlyCents: 360, freeMinutes: 60, dailyCapCents: nil, tiers: [])]
        )
        let repository = StaticParkingRepository(locations: [location])

        let options = await repository.options(near: .init(latitude: -37.5622, longitude: 143.8581), duration: .twoHours, at: now)

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].classification, .staticOnly)
        XCTAssertEqual(options[0].availabilityLabel, "Availability unknown")
        XCTAssertEqual(options[0].restrictionLabel, "3P until 12:00 am")
        XCTAssertEqual(options[0].price.primaryText, "$3.60 for 2 hours")
        XCTAssertEqual(options[0].sourceCheckedAt, location.source.checkedAt)
    }

    func testExcludesLocationsOutsideRadiusAndRulesShorterThanRequestedStay() async {
        let nearbyShort = fixture(
            id: "short", name: "One hour", coordinate: .melbourneCBD,
            schedules: [.init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60, maxStayMinutes: 60,
                              restrictionText: "1P", appliesOnPublicHolidays: true, outsideWindowMeansUnrestricted: false)]
        )
        let far = fixture(id: "far", name: "Far away", coordinate: .init(latitude: -36.7, longitude: 144.3))
        let repository = StaticParkingRepository(locations: [nearbyShort, far], radiusMetres: 2_000)

        let options = await repository.options(near: .melbourneCBD, duration: .twoHours, at: now)

        XCTAssertTrue(options.isEmpty)
    }

    func testOfficialCouncilLocationWinsOverNearbyOSMDuplicate() async {
        let official = fixture(id: "official", name: "Council car park", coordinate: .melbourneCBD)
        let osm = fixture(
            id: "osm-way-1", name: "Mapped public parking",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude + 0.0001, longitude: Coordinate.melbourneCBD.longitude),
            sourceID: "openstreetmap-victoria-parking", sourceName: "OpenStreetMap contributors"
        )
        let repository = StaticParkingRepository(locations: [osm, official])

        let options = await repository.options(near: .melbourneCBD, duration: .oneHour, at: now)

        XCTAssertEqual(options.map(\.id), ["static-official"])
    }

    func testResultLimitPreventsDenseStaticMapsFromBecomingCluttered() async {
        let locations = (0..<80).map { index in
            fixture(
                id: "location-\(index)", name: "Parking \(index)",
                coordinate: .init(latitude: Coordinate.melbourneCBD.latitude + Double(index) * 0.00001, longitude: Coordinate.melbourneCBD.longitude)
            )
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 24)

        let options = await repository.options(near: .melbourneCBD, duration: .oneHour, at: now)

        XCTAssertEqual(options.count, 24)
    }

    func testValidatedEvidencePromotesStaticLocationToExplicitPrediction() async {
        let location = StaticParkingLocation(
            id: "surveyed", name: "Surveyed car park", municipality: "Fixture", coordinate: .melbourneCBD,
            kind: .offStreet, archetype: .cbdRetail, capacity: 100, accessibleSpaces: 2,
            schedules: [], tariffs: [],
            source: .init(id: "official-council", name: "Official Council", sourceURL: URL(string: "https://example.com")!,
                          licenseName: "Official", licenseURL: nil, datasetUpdatedAt: now, checkedAt: now),
            classification: .staticOnly,
            predictionEvidence: .init(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.7,
                                      sourceDescription: "Held-out occupancy survey", observedThrough: now)
        )
        let repository = StaticParkingRepository(locations: [location])

        let option = await repository.options(near: .melbourneCBD, duration: .oneHour, at: now).first

        XCTAssertEqual(option?.classification, .predicted)
        XCTAssertNotNil(option?.available)
        XCTAssertEqual(option?.total, 100)
        XCTAssertEqual(option?.pinLabel.first, "~")
        XCTAssertTrue(option?.warningText?.contains("not live") == true)
    }

    private func fixture(
        id: String,
        name: String,
        coordinate: Coordinate,
        schedules: [ParkingSchedule] = [],
        tariffs: [ParkingTariff] = [],
        sourceID: String = "official-council",
        sourceName: String = "Official Council"
    ) -> StaticParkingLocation {
        .init(
            id: id, name: name, municipality: "Fixture", coordinate: coordinate, kind: .offStreet, archetype: .general,
            capacity: 40, accessibleSpaces: 2, schedules: schedules, tariffs: tariffs,
            source: .init(id: sourceID, name: sourceName, sourceURL: URL(string: "https://example.com/parking")!,
                          licenseName: "Official public page", licenseURL: nil,
                          datasetUpdatedAt: now.addingTimeInterval(-3_600), checkedAt: now.addingTimeInterval(-1_800)),
            classification: .staticOnly, predictionEvidence: nil
        )
    }
}

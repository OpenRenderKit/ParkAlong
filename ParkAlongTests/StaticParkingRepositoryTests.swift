import XCTest
@testable import ParkAlong

final class StaticParkingRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_000_000)

    func testScheduleDecodesUnparsedConditionForFailClosedHandling() throws {
        let data = Data("""
        {
          "days": [2],
          "startMinutes": 0,
          "endMinutes": 1440,
          "maxStayMinutes": null,
          "restrictionText": "Unparsed OSM opening hours",
          "appliesOnPublicHolidays": false,
          "outsideWindowMeansUnrestricted": false,
          "unparsedCondition": "sunrise-sunset"
        }
        """.utf8)

        let schedule = try BundleDataLoader.decoder().decode(ParkingSchedule.self, from: data)

        XCTAssertEqual(schedule.unparsedCondition, "sunrise-sunset")
    }

    func testTariffDecodesUnparsedConditionForFailClosedHandling() throws {
        let data = Data("""
        {
          "effectiveFrom": "2026-01-01T00:00:00Z",
          "effectiveTo": null,
          "days": [2],
          "startMinutes": 0,
          "endMinutes": 1440,
          "hourlyCents": null,
          "freeMinutes": 0,
          "dailyCapCents": null,
          "tiers": [],
          "unparsedCondition": "EUR 2/hour"
        }
        """.utf8)

        let tariff = try BundleDataLoader.decoder().decode(ParkingTariff.self, from: data)

        XCTAssertEqual(tariff.unparsedCondition, "EUR 2/hour")
    }

    func testGeneratedVictorianCatalogDecodesFromAppBundle() throws {
        let locations = try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
        let manifest = try BundleDataLoader.load(StaticCatalogManifest.self, named: "victoria_static_manifest")
        XCTAssertEqual(locations.count, manifest.recordCount)
        XCTAssertEqual(manifest.sourceCounts.values.reduce(0, +), manifest.recordCount)
        XCTAssertEqual(manifest.outputSHA256.count, 64)
        XCTAssertGreaterThanOrEqual(Set(locations.map(\.source.id)).count, 18)
        XCTAssertTrue(locations.contains(where: { $0.source.id == "openstreetmap-victoria-parking" }))
        XCTAssertTrue(locations.contains(where: { $0.source.id == "maribyrnong-parking-explorer" }))
        XCTAssertTrue(locations.contains(where: { $0.id == "bendigo-hargreaves-multistorey" && $0.tariffs.first?.hourlyCents == 240 }))
    }

    func testBundledCatalogDecodeCompletesWithinInteractiveStartupBudget() throws {
        let clock = ContinuousClock()

        let elapsed = try clock.measure {
            _ = try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
        }

        print("PARKALONG_PERF bundled_catalog_decode_seconds=\(elapsed.components.seconds).\(elapsed.components.attoseconds)")
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    func testRealCatalogStreetViewportQueryPerformance() async throws {
        let locations = try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
        let repository = StaticParkingRepository(locations: locations, resultLimit: 48)
        let viewports = (0..<8).map { step in
            ParkingViewport(
                south: -37.84 + Double(step) * 0.0004,
                west: 144.92 + Double(step) * 0.0004,
                north: -37.78 + Double(step) * 0.0004,
                east: 145.00 + Double(step) * 0.0004,
                zoomLevel: 14
            )
        }
        let clock = ContinuousClock()
        var visibleCounts: [Int] = []

        let elapsed = await clock.measure {
            for viewport in viewports {
                visibleCounts.append(await repository.options(in: viewport, plan: plan(.twoHours)).count)
            }
        }

        print("PARKALONG_PERF eight_street_viewport_queries_seconds=\(elapsed.components.seconds).\(elapsed.components.attoseconds) visible_counts=\(visibleCounts)")
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    func testBundledForecastValidationDecodesWithMeasuredReleaseEvidence() throws {
        let records = try BundleDataLoader.load([ForecastValidationRecord].self, named: "historical_validation")

        XCTAssertFalse(records.isEmpty)
        XCTAssertEqual(Set(records.map(\.segmentKey)).count, records.count)
        XCTAssertTrue(records.allSatisfy { $0.sampleCount > 0 })
        XCTAssertTrue(records.allSatisfy { (0...1).contains($0.normalizedMAE) })
        XCTAssertTrue(records.allSatisfy { (0...1).contains($0.brierScore) })
        XCTAssertTrue(records.allSatisfy { (0...1).contains($0.intervalCoverage) })
        XCTAssertTrue(records.allSatisfy { (0...1).contains($0.intervalRadius ?? -1) })
        XCTAssertTrue(records.allSatisfy { $0.modelVersion == "melbourne-events-v3-2019-conformal" })
    }

    func testLazyLoaderSuppliesCatalogOffTheLaunchPath() async {
        let location = fixture(id: "lazy", name: "Lazy catalog", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(loader: { [location] })

        let options = await repository.options(in: viewport(center: .melbourneCBD), plan: plan(.oneHour))

        XCTAssertEqual(options.map(\.title), ["Lazy catalog"])
    }

    func testExactViewportAndPlanQueryUsesCacheAndPlanChangeInvalidatesIt() async {
        let location = fixture(id: "cache", name: "Cached location", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(locations: [location])
        let queryViewport = viewport(center: .melbourneCBD)

        let first = await repository.options(in: queryViewport, plan: plan(.oneHour))
        let second = await repository.options(in: queryViewport, plan: plan(.oneHour))
        let cachedMetrics = await repository.cacheMetrics()
        _ = await repository.options(in: queryViewport, plan: plan(.twoHours))
        let invalidatedMetrics = await repository.cacheMetrics()

        XCTAssertEqual(first, second)
        XCTAssertEqual(cachedMetrics, .init(hits: 1, misses: 1, entries: 1))
        XCTAssertEqual(invalidatedMetrics.hits, 1)
        XCTAssertEqual(invalidatedMetrics.misses, 2)
        XCTAssertEqual(invalidatedMetrics.entries, 1)
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

        let options = await repository.options(in: viewport(center: .init(latitude: -37.5622, longitude: 143.8581)), plan: plan(.twoHours))

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
        let repository = StaticParkingRepository(locations: [nearbyShort, far])

        let options = await repository.options(in: viewport(center: .melbourneCBD), plan: plan(.twoHours))

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

        let options = await repository.options(in: viewport(center: .melbourneCBD), plan: plan(.oneHour))

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

        let options = await repository.options(in: viewport(center: .melbourneCBD), plan: plan(.oneHour))

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
                                      sourceDescription: "Held-out occupancy survey", observedThrough: now,
                                      brierScore: 0.12, intervalCoverage: 0.9, modelVersion: "survey-v2")
        )
        let repository = StaticParkingRepository(locations: [location])

        let option = await repository.options(in: viewport(center: .melbourneCBD), plan: plan(.oneHour)).first

        XCTAssertEqual(option?.classification, .predicted)
        XCTAssertNotNil(option?.available)
        XCTAssertEqual(option?.total, 100)
        XCTAssertEqual(option?.pinLabel.first, "~")
        XCTAssertTrue(option?.warningText?.contains("not live") == true)
    }

    func testPublicHolidayPlanIsPassedIntoStaticDemandContext() async {
        let location = StaticParkingLocation(
            id: "station", name: "Station car park", municipality: "Fixture", coordinate: .melbourneCBD,
            kind: .offStreet, archetype: .stationCommuter, capacity: 100, accessibleSpaces: nil,
            schedules: [], tariffs: [],
            source: .init(id: "official-council", name: "Official Council", sourceURL: URL(string: "https://example.com")!,
                          licenseName: "Official", licenseURL: nil, datasetUpdatedAt: now, checkedAt: now),
            classification: .staticOnly,
            predictionEvidence: .init(
                sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.7,
                sourceDescription: "Held-out occupancy survey", observedThrough: now,
                brierScore: 0.12, intervalCoverage: 0.9, modelVersion: "survey-v2"
            )
        )
        let repository = StaticParkingRepository(locations: [location])
        let ordinary = ParkingPlan(arrival: now, duration: .oneHour)
        let holiday = ParkingPlan(arrival: now, duration: .oneHour, isPublicHoliday: true)

        let ordinaryExpected = await repository.options(in: viewport(center: .melbourneCBD), plan: ordinary).first?.prediction?.expectedAvailable
        let holidayExpected = await repository.options(in: viewport(center: .melbourneCBD), plan: holiday).first?.prediction?.expectedAvailable

        XCTAssertNotNil(ordinaryExpected)
        XCTAssertNotNil(holidayExpected)
        XCTAssertGreaterThan(holidayExpected!, ordinaryExpected!)
    }

    func testViewportFiltersByVisibleBoundsInsteadOfAFixedDestinationRadius() async {
        let west = fixture(id: "west", name: "Visible west", coordinate: .init(latitude: -37.81, longitude: 144.90))
        let east = fixture(id: "east", name: "Visible east", coordinate: .init(latitude: -37.81, longitude: 145.02))
        let outside = fixture(id: "outside", name: "Outside", coordinate: .init(latitude: -37.81, longitude: 145.20))
        let repository = StaticParkingRepository(locations: [west, east, outside], resultLimit: 20)
        let visible = ParkingViewport(south: -37.90, west: 144.85, north: -37.75, east: 145.05, zoomLevel: 12)

        let options = await repository.options(in: visible, plan: plan(.oneHour))

        XCTAssertEqual(Set(options.map(\.title)), ["Visible west", "Visible east"])
    }

    func testWideViewportClustersDenseParkingAndKeepsZoomTarget() async {
        let locations = (0..<30).map { index in
            fixture(
                id: "cluster-\(index)", name: "Parking \(index)",
                coordinate: .init(
                    latitude: Coordinate.melbourneCBD.latitude + Double(index % 5) * 0.00005,
                    longitude: Coordinate.melbourneCBD.longitude + Double(index / 5) * 0.00005
                )
            )
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 80)
        let wide = ParkingViewport(south: -38.0, west: 144.7, north: -37.6, east: 145.1, zoomLevel: 9)

        let options = await repository.options(in: wide, plan: plan(.oneHour))

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].clusterCount, 30)
        XCTAssertEqual(options[0].pinLabel, "30")
        XCTAssertEqual(options[0].clusterViewport?.zoomLevel, 11)
    }

    func testWideViewportClustersEveryVisibleRecordInsteadOfTruncatingAroundTheCentre() async {
        let locations = (0..<900).map { index in
            let row = index / 30
            let column = index % 30
            return fixture(
                id: "statewide-\(index)", name: "Parking \(index)",
                coordinate: .init(
                    latitude: -38.8 + Double(row) * 0.16,
                    longitude: 141.2 + Double(column) * 0.28
                )
            )
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 24)
        let victoria = ParkingViewport(south: -39.0, west: 140.9, north: -33.8, east: 149.8, zoomLevel: 6)

        let options = await repository.options(in: victoria, plan: plan(.oneHour))

        XCTAssertEqual(options.map { $0.clusterCount ?? 1 }.reduce(0, +), 900)
        XCTAssertTrue(options.count > 24)
    }

    func testViewportPaddingKeepsNearEdgePinsStableDuringSmallPans() {
        let viewport = ParkingViewport(south: -38.0, west: 144.0, north: -37.0, east: 145.0, zoomLevel: 10)

        let padded = viewport.padded(by: 0.2)

        XCTAssertEqual(padded.south, -38.2, accuracy: 0.0001)
        XCTAssertEqual(padded.north, -36.8, accuracy: 0.0001)
        XCTAssertEqual(padded.west, 143.8, accuracy: 0.0001)
        XCTAssertEqual(padded.east, 145.2, accuracy: 0.0001)
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

    private func plan(_ duration: StayDuration) -> ParkingPlan {
        ParkingPlan(arrival: now, duration: duration)
    }

    private func viewport(center: Coordinate) -> ParkingViewport {
        .init(
            south: center.latitude - 0.02, west: center.longitude - 0.02,
            north: center.latitude + 0.02, east: center.longitude + 0.02,
            zoomLevel: 14
        )
    }
}

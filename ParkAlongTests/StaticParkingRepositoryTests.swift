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

    func testStaticKindDecodesUnknownWithoutGuessingOnOrOffStreet() throws {
        let decoder = BundleDataLoader.decoder()

        XCTAssertEqual(try decoder.decode(StaticParkingKind.self, from: Data("\"unknown\"".utf8)), .unknown)
        XCTAssertEqual(try decoder.decode(StaticParkingKind.self, from: Data("\"on_street\"".utf8)), .onStreet)
        XCTAssertEqual(try decoder.decode(StaticParkingKind.self, from: Data("\"off_street\"".utf8)), .offStreet)
        XCTAssertThrowsError(try decoder.decode(StaticParkingKind.self, from: Data("\"street\"".utf8)))
    }

    func testStaticLocationJSONDecodesUnknownKind() throws {
        let data = Data("""
        {
          "id": "accessible-unknown",
          "name": "Accessible parking bay",
          "municipality": "Latrobe",
          "coordinate": {"latitude": -38.237, "longitude": 146.414},
          "kind": "unknown",
          "archetype": "general",
          "capacity": 1,
          "accessibleSpaces": 1,
          "schedules": [],
          "tariffs": [],
          "source": {
            "id": "latrobe-accessible-parking",
            "name": "Latrobe City accessible parking",
            "sourceURL": "https://example.com/accessible",
            "licenseName": "Official public page",
            "licenseURL": null,
            "datasetUpdatedAt": "2026-01-01T00:00:00Z",
            "checkedAt": "2026-09-19T00:00:00Z"
          },
          "classification": "static_only",
          "predictionEvidence": null
        }
        """.utf8)

        let location = try BundleDataLoader.decoder().decode(StaticParkingLocation.self, from: data)

        XCTAssertEqual(location.kind, .unknown)
        XCTAssertEqual(location.kind.rawValue, "unknown")
        XCTAssertNil(location.locality)
    }

    func testStaticLocationJSONDecodesMissingLocality() throws {
        let location = try BundleDataLoader.decoder().decode(StaticParkingLocation.self, from: staticLocationJSON())

        XCTAssertNil(location.locality)
        XCTAssertEqual(location.municipality, "Latrobe")
        XCTAssertEqual(location.locationLabel, "Latrobe")
        XCTAssertEqual(location.name, "Accessible parking bay")
        XCTAssertEqual(location.kind, .unknown)
        XCTAssertEqual(location.classification, .staticOnly)
        XCTAssertEqual(location.source.name, "Latrobe City accessible parking")
    }

    func testStaticLocationJSONDecodesAuthoritativeLocality() throws {
        let location = try BundleDataLoader.decoder().decode(
            StaticParkingLocation.self,
            from: staticLocationJSON(localityLine: "          \"locality\": \"Glen Waverley\",\n")
        )

        XCTAssertEqual(location.locality, "Glen Waverley")
        XCTAssertEqual(location.municipality, "Latrobe")
        XCTAssertEqual(location.locationLabel, "Glen Waverley, Latrobe")
        XCTAssertEqual(location.name, "Accessible parking bay")
        XCTAssertEqual(location.kind, .unknown)
        XCTAssertEqual(location.source.name, "Latrobe City accessible parking")
    }

    func testUnknownStaticKindMapsToParkingOptionWithoutChoosingOnOrOffStreet() async {
        let unknown = fixture(id: "unknown", name: "Accessible bay", coordinate: .melbourneCBD, kind: .unknown)
        let onStreet = fixture(
            id: "on", name: "Street bay",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude + 0.001, longitude: Coordinate.melbourneCBD.longitude),
            kind: .onStreet
        )
        let offStreet = fixture(
            id: "off", name: "Car park",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude - 0.001, longitude: Coordinate.melbourneCBD.longitude),
            kind: .offStreet
        )
        let repository = StaticParkingRepository(locations: [unknown, onStreet, offStreet])

        let options = await repository.options(in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.oneHour))
        let byID = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })

        XCTAssertEqual(byID["static-unknown"]?.kind, .unknown)
        XCTAssertEqual(byID["static-unknown"]?.kind.rawValue, "Parking")
        XCTAssertEqual(byID["static-on"]?.kind, .onStreet)
        XCTAssertEqual(byID["static-off"]?.kind, .offStreet)
    }

    func testGeneratedVictorianCatalogDecodesFromAppBundle() throws {
        let locations = try BundleDataLoader.load([StaticParkingLocation].self, named: "victoria_static_parking")
        let manifest = try BundleDataLoader.load(StaticCatalogManifest.self, named: "victoria_static_manifest")
        XCTAssertEqual(locations.count, manifest.recordCount)
        XCTAssertEqual(manifest.sourceCounts.values.reduce(0, +), manifest.recordCount)
        XCTAssertEqual(manifest.sourceCount, Set(locations.map(\.source.id)).count)
        XCTAssertEqual(manifest.municipalityCount, Set(locations.map(\.municipality)).count)
        XCTAssertEqual(manifest.accessibleRecordCount, locations.filter { ($0.accessibleSpaces ?? 0) > 0 }.count)
        XCTAssertEqual(manifest.sourceAttributions?.count, manifest.sourceCount)
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

        print("PARKALONG_PERF bundled_catalog_decode_seconds=\(seconds(elapsed))")
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
                visibleCounts.append(await repository.options(
                    in: viewport,
                    relativeTo: reference(coordinate: viewport.center),
                    plan: plan(.twoHours)
                ).count)
            }
        }

        print("PARKALONG_PERF eight_street_viewport_queries_seconds=\(seconds(elapsed)) visible_counts=\(visibleCounts)")
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

        let options = await repository.options(
            in: viewport(center: .melbourneCBD),
            relativeTo: reference(),
            plan: plan(.oneHour)
        )

        XCTAssertEqual(options.map(\.title), ["Lazy catalog"])
    }

    func testExactViewportAndPlanQueryUsesCacheAndPlanChangeInvalidatesIt() async {
        let location = fixture(id: "cache", name: "Cached location", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(locations: [location])
        let queryViewport = viewport(center: .melbourneCBD)

        let first = await repository.options(in: queryViewport, relativeTo: reference(), plan: plan(.oneHour))
        let second = await repository.options(in: queryViewport, relativeTo: reference(), plan: plan(.oneHour))
        let cachedMetrics = await repository.cacheMetrics()
        _ = await repository.options(in: queryViewport, relativeTo: reference(), plan: plan(.twoHours))
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

        let destination = Coordinate(latitude: -37.5622, longitude: 143.8581)
        let options = await repository.options(
            in: viewport(center: destination),
            relativeTo: reference(coordinate: destination),
            plan: plan(.twoHours)
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].classification, .staticOnly)
        XCTAssertEqual(options[0].availabilityLabel, "Availability unknown")
        XCTAssertEqual(options[0].restrictionLabel, "3P until 12:00 am")
        XCTAssertEqual(options[0].price.primaryText, "$3.60 for 2 hours")
        XCTAssertEqual(options[0].sourceCheckedAt, location.source.checkedAt)
    }

    func testStaticProximityUsesDestinationInsteadOfViewportCentre() async throws {
        let location = fixture(id: "destination-distance", name: "Destination distance", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(locations: [location])
        let mapCentre = Coordinate(latitude: -37.81, longitude: 144.96)
        let destination = Coordinate(latitude: -37.79, longitude: 144.93)
        let queryViewport = viewport(center: mapCentre)

        let options = await repository.options(
            in: queryViewport,
            relativeTo: reference(coordinate: destination, label: "Selected destination"),
            plan: plan(.oneHour)
        )
        let option = try XCTUnwrap(options.first)

        let expected = ParkingRepository.distance(from: location.coordinate, to: destination)
        XCTAssertEqual(option.proximity.straightLineMetres, expected, accuracy: 0.01)
        XCTAssertEqual(option.proximity.reference.label, "Selected destination")
        XCTAssertNotEqual(option.proximity.straightLineMetres, ParkingRepository.distance(from: location.coordinate, to: mapCentre))
    }

    func testExcludesLocationsOutsideRadiusAndRulesShorterThanRequestedStay() async {
        let nearbyShort = fixture(
            id: "short", name: "One hour", coordinate: .melbourneCBD,
            schedules: [.init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60, maxStayMinutes: 60,
                              restrictionText: "1P", appliesOnPublicHolidays: true, outsideWindowMeansUnrestricted: false)]
        )
        let far = fixture(id: "far", name: "Far away", coordinate: .init(latitude: -36.7, longitude: 144.3))
        let repository = StaticParkingRepository(locations: [nearbyShort, far])

        let options = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.twoHours)
        )

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

        let options = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.oneHour)
        )

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

        let options = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.oneHour)
        )

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

        let option = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.oneHour)
        ).first

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

        let ordinaryExpected = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: ordinary
        ).first?.prediction?.expectedAvailable
        let holidayExpected = await repository.options(
            in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: holiday
        ).first?.prediction?.expectedAvailable

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

        let options = await repository.options(
            in: visible, relativeTo: reference(coordinate: visible.center), plan: plan(.oneHour)
        )

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

        let options = await repository.options(
            in: wide, relativeTo: reference(coordinate: wide.center), plan: plan(.oneHour)
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].clusterCount, 30)
        XCTAssertEqual(options[0].pinLabel, "30")
        let target = try! XCTUnwrap(options[0].clusterViewport)
        XCTAssertEqual(target.zoomLevel, log2(360 / max(target.longitudeSpan, 0.002)), accuracy: 0.000_001)
    }

    func testDisplayedClusterExpandsToItsEligibleChildren() async throws {
        let locations = (0..<30).map { index in
            fixture(
                id: "expand-\(index)", name: "Parking \(index)",
                coordinate: .init(
                    latitude: Coordinate.melbourneCBD.latitude + Double(index % 5) * 0.00005,
                    longitude: Coordinate.melbourneCBD.longitude + Double(index / 5) * 0.00005
                )
            )
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 80)
        let wide = ParkingViewport(south: -38.0, west: 144.7, north: -37.6, east: 145.1, zoomLevel: 9)
        let clustered = await repository.options(in: wide, relativeTo: reference(coordinate: wide.center), plan: plan(.oneHour))
        let cluster = try XCTUnwrap(clustered.first)
        let target = try XCTUnwrap(cluster.clusterViewport)

        let expanded = await repository.options(in: target, relativeTo: reference(coordinate: target.center), plan: plan(.oneHour))

        XCTAssertEqual(expanded.count, 30)
        XCTAssertTrue(expanded.allSatisfy { $0.clusterCount == nil })
        XCTAssertTrue(expanded.allSatisfy { target.contains($0.coordinate) })
    }

    func testBoundaryClusterTargetContainsAndRevealsEligibleChildren() async throws {
        let locations: [StaticParkingLocation] = (0..<8).map { index in
            let row: Int = index % 2
            let column: Int = index / 2
            let latitude: Double = -37.80002 + Double(row) * 0.00004
            let longitude: Double = 145.00002 + Double(column) * 0.00004
            let coordinate = Coordinate(latitude: latitude, longitude: longitude)
            let identifier: String = "edge-\(index)"
            let title: String = "Edge parking \(index)"
            return fixture(id: identifier, name: title, coordinate: coordinate)
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 80)
        let wide = ParkingViewport(south: -38.0, west: 144.8, north: -37.8, east: 145.0, zoomLevel: 10)
        let clustered: [ParkingOption] = await repository.options(in: wide, relativeTo: reference(coordinate: wide.center), plan: plan(.oneHour))
        let cluster: ParkingOption = try XCTUnwrap(clustered.first(where: { $0.clusterCount != nil }))
        let target: ParkingViewport = try XCTUnwrap(cluster.clusterViewport)

        let expanded = await repository.options(in: target, relativeTo: reference(coordinate: target.center), plan: plan(.oneHour))

        XCTAssertEqual(expanded.count, locations.count)
        XCTAssertTrue(expanded.allSatisfy { $0.clusterCount == nil && target.contains($0.coordinate) })
    }

    func testQueryCacheDoesNotReuseProximityFromAnotherDestination() async {
        let location = fixture(id: "cache-proximity", name: "Cached proximity", coordinate: .melbourneCBD)
        let repository = StaticParkingRepository(locations: [location])
        let queryViewport = viewport(center: .melbourneCBD)

        let first = await repository.options(
            in: queryViewport, relativeTo: reference(label: "First destination"), plan: plan(.oneHour)
        )
        let second = await repository.options(
            in: queryViewport, relativeTo: reference(label: "Second destination"), plan: plan(.oneHour)
        )
        let metrics = await repository.cacheMetrics()

        XCTAssertEqual(first.first?.proximity.reference.label, "First destination")
        XCTAssertEqual(second.first?.proximity.reference.label, "Second destination")
        XCTAssertEqual(metrics.hits, 0)
        XCTAssertEqual(metrics.misses, 2)
        XCTAssertEqual(metrics.entries, 2)
    }

    func testZoomedOutClusterUsesUnknownKindForMixedAndUnknownMembers() async throws {
        let kinds: [StaticParkingKind] = [.unknown, .onStreet, .offStreet]
        let locations = kinds.enumerated().map { index, kind in
            fixture(
                id: "mixed-\(index)",
                name: "Parking \(index)",
                coordinate: .init(
                    latitude: Coordinate.melbourneCBD.latitude + Double(index) * 0.00005,
                    longitude: Coordinate.melbourneCBD.longitude
                ),
                kind: kind,
                municipality: "Monash",
                locality: "Glen Waverley"
            )
        }
        let repository = StaticParkingRepository(locations: locations, resultLimit: 80)
        let wide = ParkingViewport(south: -38.0, west: 144.7, north: -37.6, east: 145.1, zoomLevel: 9)

        let options = await repository.options(in: wide, relativeTo: reference(coordinate: wide.center), plan: plan(.oneHour))

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].kind, .unknown)
        XCTAssertEqual(options[0].kind.rawValue, "Parking")
        XCTAssertEqual(options[0].kind.rawValue.uppercased(), "PARKING")
        XCTAssertNotEqual(options[0].kind, .offStreet)
        XCTAssertNotEqual(options[0].kind, .onStreet)
        XCTAssertEqual(options[0].clusterCount, 3)
        XCTAssertEqual(options[0].title, "3 parking locations")
        XCTAssertEqual(options[0].locationLabel, "Glen Waverley, Monash")
        XCTAssertEqual(options[0].pinLabel, "3")
        let target = try XCTUnwrap(options[0].clusterViewport)
        XCTAssertEqual(target.zoomLevel, log2(360 / max(target.longitudeSpan, 0.002)), accuracy: 0.000_001)
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

        let options = await repository.options(
            in: victoria, relativeTo: reference(coordinate: victoria.center), plan: plan(.oneHour)
        )

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

    func testSearchMatchesGlenWaverleyLocalitySpelling() async {
        let glenWaverley = fixture(
            id: "glen-waverley",
            name: "Kingsway car park",
            coordinate: .init(latitude: -37.880, longitude: 145.162),
            municipality: "Monash",
            locality: "Glen Waverley"
        )
        let elsewhere = fixture(
            id: "elsewhere",
            name: "Unrelated car park",
            coordinate: .melbourneCBD,
            municipality: "Melbourne",
            locality: "Carlton"
        )
        let repository = StaticParkingRepository(locations: [glenWaverley, elsewhere])

        let matches = await repository.search(
            "Glen Waverley",
            near: viewport(center: glenWaverley.coordinate),
            relativeTo: reference(coordinate: glenWaverley.coordinate),
            plan: plan(.oneHour)
        )

        XCTAssertEqual(matches.map(\.id), ["static-glen-waverley"])
        XCTAssertEqual(matches.first?.title, "Kingsway car park")
        XCTAssertEqual(matches.first?.locationLabel, "Glen Waverley, Monash")
        XCTAssertEqual(matches.first?.provider, "Official Council")
        XCTAssertEqual(matches.first?.kind, .offStreet)
        XCTAssertEqual(matches.first?.classification, .staticOnly)
    }

    func testOptionLocationLabelFallsBackAndDeduplicatesLocality() async {
        let withLocality = fixture(
            id: "with-locality", name: "Kingsway car park",
            coordinate: .melbourneCBD, municipality: "Monash", locality: "Glen Waverley"
        )
        let missing = fixture(
            id: "missing-locality", name: "Sturt Street",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude + 0.001, longitude: Coordinate.melbourneCBD.longitude),
            municipality: "Ballarat"
        )
        let duplicate = fixture(
            id: "duplicate-locality", name: "Library car park",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude - 0.001, longitude: Coordinate.melbourneCBD.longitude),
            municipality: "Hamilton", locality: "Hamilton"
        )
        let blank = fixture(
            id: "blank-locality", name: "Werribee bay",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude, longitude: Coordinate.melbourneCBD.longitude + 0.001),
            municipality: "Wyndham", locality: "   "
        )
        let caseDuplicate = fixture(
            id: "case-duplicate", name: "Casey bay",
            coordinate: .init(latitude: Coordinate.melbourneCBD.latitude, longitude: Coordinate.melbourneCBD.longitude - 0.001),
            municipality: "Casey", locality: "casey"
        )
        XCTAssertEqual(withLocality.locationLabel, "Glen Waverley, Monash")
        XCTAssertEqual(missing.locationLabel, "Ballarat")
        XCTAssertEqual(duplicate.locationLabel, "Hamilton")
        XCTAssertEqual(blank.locationLabel, "Wyndham")
        XCTAssertEqual(caseDuplicate.locationLabel, "Casey")

        let repository = StaticParkingRepository(
            locations: [withLocality, missing, duplicate, blank, caseDuplicate]
        )
        let options = await repository.options(in: viewport(center: .melbourneCBD), relativeTo: reference(), plan: plan(.oneHour))
        let byID = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })

        XCTAssertEqual(byID["static-with-locality"]?.locationLabel, "Glen Waverley, Monash")
        XCTAssertEqual(byID["static-with-locality"]?.title, "Kingsway car park")
        XCTAssertEqual(byID["static-with-locality"]?.provider, "Official Council")
        XCTAssertEqual(byID["static-missing-locality"]?.locationLabel, "Ballarat")
        XCTAssertEqual(byID["static-duplicate-locality"]?.locationLabel, "Hamilton")
        XCTAssertEqual(byID["static-blank-locality"]?.locationLabel, "Wyndham")
        XCTAssertEqual(byID["static-case-duplicate"]?.locationLabel, "Casey")
        XCTAssertEqual(byID["static-with-locality"]?.kind, .offStreet)
        XCTAssertEqual(byID["static-with-locality"]?.classification, .staticOnly)
    }

    private func staticLocationJSON(localityLine: String = "") -> Data {
        Data("""
        {
          "id": "accessible-unknown",
          "name": "Accessible parking bay",
          "municipality": "Latrobe",
        \(localityLine)          "coordinate": {"latitude": -38.237, "longitude": 146.414},
          "kind": "unknown",
          "archetype": "general",
          "capacity": 1,
          "accessibleSpaces": 1,
          "schedules": [],
          "tariffs": [],
          "source": {
            "id": "latrobe-accessible-parking",
            "name": "Latrobe City accessible parking",
            "sourceURL": "https://example.com/accessible",
            "licenseName": "Official public page",
            "licenseURL": null,
            "datasetUpdatedAt": "2026-01-01T00:00:00Z",
            "checkedAt": "2026-09-19T00:00:00Z"
          },
          "classification": "static_only",
          "predictionEvidence": null
        }
        """.utf8)
    }

    private func fixture(
        id: String,
        name: String,
        coordinate: Coordinate,
        kind: StaticParkingKind = .offStreet,
        municipality: String = "Fixture",
        locality: String? = nil,
        schedules: [ParkingSchedule] = [],
        tariffs: [ParkingTariff] = [],
        sourceID: String = "official-council",
        sourceName: String = "Official Council"
    ) -> StaticParkingLocation {
        .init(
            id: id, name: name, municipality: municipality, locality: locality, coordinate: coordinate,
            kind: kind, archetype: .general, capacity: 40, accessibleSpaces: 2, schedules: schedules, tariffs: tariffs,
            source: .init(id: sourceID, name: sourceName, sourceURL: URL(string: "https://example.com/parking")!,
                          licenseName: "Official public page", licenseURL: nil,
                          datasetUpdatedAt: now.addingTimeInterval(-3_600), checkedAt: now.addingTimeInterval(-1_800)),
            classification: .staticOnly, predictionEvidence: nil
        )
    }

    private func plan(_ duration: StayDuration) -> ParkingPlan {
        ParkingPlan(arrival: now, duration: duration)
    }

    private func reference(
        coordinate: Coordinate = .melbourneCBD,
        label: String = "Test destination"
    ) -> ParkingProximityReference {
        .init(coordinate: coordinate, label: label)
    }

    private func viewport(center: Coordinate) -> ParkingViewport {
        .init(
            south: center.latitude - 0.02, west: center.longitude - 0.02,
            north: center.latitude + 0.02, east: center.longitude + 0.02,
            zoomLevel: 14
        )
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }
}

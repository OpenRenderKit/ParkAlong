import XCTest
@testable import ParkAlong

final class ParkingOptionTests: XCTestCase {
    func testFreeRestrictionProducesAuthoritativeFreePrice() {
        let price = ParkingPriceEngine.price(payment: .free, plan: plan(hour: 10, durationMinutes: 60), coordinate: .melbourneCBD)
        XCTAssertEqual(price.primaryText, "Free")
        XCTAssertNil(price.actionURL)
    }

    func testPaidFifteenMinuteStayUsesCurrentCityFreeSessionPolicy() {
        let price = ParkingPriceEngine.price(payment: .paid, plan: plan(hour: 10, durationMinutes: 15), coordinate: .melbourneCBD)
        XCTAssertEqual(price.primaryText, "$0 for up to 15 min")
        XCTAssertEqual(price.provider, "City of Melbourne · EasyPark")
        XCTAssertNotNil(price.actionURL)
    }

    func testPaidCBDStayCalculatesTheCurrentWeekdayRate() {
        let price = ParkingPriceEngine.price(payment: .paid, plan: plan(hour: 10, durationMinutes: 120), coordinate: .melbourneCBD)
        XCTAssertEqual(price.primaryText, "$14.00 for 2 hours")
        XCTAssertEqual(price.actionLabel, "Check current CBD rate")
    }

    func testPaidCBDStaySplitsPeakAndOffPeakMinutesAtSevenPM() {
        let price = ParkingPriceEngine.price(payment: .paid, plan: plan(hour: 18, minute: 30, durationMinutes: 120), coordinate: .melbourneCBD)
        XCTAssertEqual(price.primaryText, "$9.50 for 2 hours")
    }

    func testPaidZoneOutsideTheCentralCBDDoesNotBorrowTheCBDTariff() {
        let price = ParkingPriceEngine.price(
            payment: .paid,
            plan: plan(hour: 10, durationMinutes: 120),
            coordinate: .init(latitude: -37.850, longitude: 144.980)
        )
        XCTAssertEqual(price.primaryText, "Check current price")
        XCTAssertEqual(price.actionLabel, "Check price with provider")
    }

    func testProviderRecognitionCreatesOfficialDeepLink() {
        let result = OffStreetProviderResolver.resolve(name: "Wilson Parking - Queen Victoria Market", suppliedURL: nil)
        XCTAssertEqual(result.provider, "Wilson Parking")
        XCTAssertEqual(result.url?.host, "www.wilsonparking.com.au")
    }

    func testLivePinUsesCountWithoutWarning() {
        let presentation = ParkingPinPresentation(option: option(classification: .verifiedLive, available: 3, total: 5))
        XCTAssertEqual(presentation.label, "3")
        XCTAssertEqual(presentation.palette, .liveAvailable)
        XCTAssertFalse(presentation.showsWarning)
        XCTAssertTrue(presentation.accessibilityLabel.contains("live"))
    }

    func testPredictedPinUsesPlumEstimateAndAmberWarning() {
        let presentation = ParkingPinPresentation(option: option(classification: .predicted, available: 4, total: 10))
        XCTAssertEqual(presentation.label, "~4")
        XCTAssertEqual(presentation.palette, .predictedPlum)
        XCTAssertTrue(presentation.showsWarning)
        XCTAssertTrue(presentation.accessibilityLabel.contains("estimate, not live"))
    }

    func testLocationOnlyPinUsesRedPAndAmberWarning() {
        let presentation = ParkingPinPresentation(option: option(classification: .staticOnly, available: nil, total: 40))
        XCTAssertEqual(presentation.label, "P")
        XCTAssertEqual(presentation.palette, .locationRed)
        XCTAssertTrue(presentation.showsWarning)
        XCTAssertTrue(presentation.accessibilityLabel.contains("location only, not live"))
    }

    func testFutureZoneWithoutValidatedForecastNeverShowsCurrentLiveCountAsArrivalAvailability() {
        let prediction = AvailabilityPrediction(
            expectedAvailable: nil, lowerBound: nil, upperBound: nil, probabilityAtLeastOne: nil,
            liveWeight: 0, evidenceTier: .abstained, horizonMinutes: 120, modelVersion: "old-v1",
            validation: nil, abstentionReason: .staleModel
        )

        let option = ParkingOption.onStreet(zone(prediction: prediction), plan: ParkingPlan(arrival: .now.addingTimeInterval(7_200), duration: .oneHour))

        XCTAssertEqual(option.classification, .staleHistorical)
        XCTAssertNil(option.available)
        XCTAssertNil(option.sourceTimestamp)
        XCTAssertEqual(option.pinLabel, "P")
        XCTAssertTrue(option.warningText?.contains("forecast") == true)
    }

    func testValidatedFutureZoneUsesForecastRangeInsteadOfCurrentLiveCount() {
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
            intervalCoverage: 0.9, observedThrough: .now, modelVersion: "fresh-v2"
        )
        let prediction = AvailabilityPrediction(
            expectedAvailable: 2.4, lowerBound: 1, upperBound: 4, probabilityAtLeastOne: 0.91,
            liveWeight: 0.4, evidenceTier: .liveInformed, horizonMinutes: 60, modelVersion: "fresh-v2",
            validation: validation, abstentionReason: nil
        )

        let option = ParkingOption.onStreet(zone(prediction: prediction), plan: ParkingPlan(arrival: .now.addingTimeInterval(3_600), duration: .oneHour))

        XCTAssertEqual(option.classification, .predicted)
        XCTAssertEqual(option.available, 2)
        XCTAssertEqual(option.pinLabel, "~2")
        XCTAssertNil(option.sourceTimestamp)
    }

    func testProximityCopyIsHonestAboutStraightLineDistanceAndDestination() {
        let proximity = ParkingProximity(
            straightLineMetres: 174,
            reference: .init(coordinate: .melbourneCBD, label: "Flinders Street Station")
        )

        XCTAssertEqual(proximity.rowLabel, "Distance to Flinders Street Station")
        XCTAssertEqual(proximity.displayValue, "About 150 m straight-line")
        XCTAssertEqual(proximity.caveat, "This isn’t a walking route.")
        XCTAssertEqual(
            proximity.accessibilityLabel,
            "Distance to Flinders Street Station, about 150 metres straight-line. This isn’t a walking route."
        )
        XCTAssertFalse(proximity.displayValue.localizedCaseInsensitiveContains("walk"))
        XCTAssertFalse(proximity.accessibilityLabel.localizedCaseInsensitiveContains("walking distance"))
    }

    func testProximityCopyRoundsWithoutImplyingAWalkingRoute() {
        let nearby = ParkingProximity(
            straightLineMetres: 12,
            reference: .init(coordinate: .melbourneCBD, label: "Current location")
        )
        let farther = ParkingProximity(
            straightLineMetres: 1_240,
            reference: .init(coordinate: .melbourneCBD, label: "Current location")
        )

        XCTAssertEqual(nearby.displayValue, "Under 50 m straight-line")
        XCTAssertEqual(farther.displayValue, "About 1.2 km straight-line")
        XCTAssertEqual(ParkingProximityReference(coordinate: .melbourneCBD, label: "  ").label, "destination")
    }

    func testSuggestionExplainsTheRankingInputsWithoutExposingAScore() {
        var best = zone(prediction: PredictionEngine.estimate(
            liveAvailable: 4,
            trustedBayCount: 10,
            historicalOccupiedRatio: 0.5,
            etaMinutes: 0,
            validation: nil,
            forecastDate: .now
        ))
        best.isSuggested = true

        let option = ParkingOption.onStreet(best, plan: ParkingPlan(arrival: .now, duration: .oneHour))

        XCTAssertEqual(
            option.recommendationExplanation,
            "We compare street parking found in this map area. Expected available spaces matter most, followed by straight-line distance to Test destination, then the chance of finding a space."
        )
        XCTAssertFalse(option.recommendationExplanation?.contains("%") == true)
        XCTAssertFalse(option.recommendationExplanation?.localizedCaseInsensitiveContains("score") == true)
        XCTAssertFalse(option.recommendationExplanation?.localizedCaseInsensitiveContains("guarantee") == true)
        XCTAssertFalse(option.recommendationExplanation?.localizedCaseInsensitiveContains("walk") == true)
    }

    @MainActor
    func testSuggestedStreetParkingCardUsesLiveCountOnlyForImmediateObservation() {
        var live = zone(
            prediction: PredictionEngine.estimate(
                liveAvailable: 4,
                trustedBayCount: 7,
                historicalOccupiedRatio: 0.5,
                etaMinutes: 0,
                validation: nil,
                forecastDate: .now
            ),
            available: 4,
            total: 7
        )
        live.isSuggested = true

        let option = ParkingOption.onStreet(live, plan: ParkingPlan(arrival: .now, duration: .oneHour))
        let spoken = SuggestedOnStreetAreaButton.accessibilityText(for: option)

        XCTAssertEqual(option.classification, .verifiedLive)
        XCTAssertEqual(option.pinLabel, "4")
        XCTAssertEqual(option.availabilityLabel, "4 of 7 available now")
        XCTAssertEqual(
            spoken,
            "Suggested street parking, Collins Street, 4 of 7 available now. This is a suggestion, not a guarantee."
        )
    }

    @MainActor
    func testSuggestedStreetParkingCardDoesNotShowLiveCountForAValidatedFutureArrival() {
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
            intervalCoverage: 0.9, observedThrough: .now, modelVersion: "fresh-v2"
        )
        var future = zone(
            prediction: AvailabilityPrediction(
                expectedAvailable: 2.4, lowerBound: 1, upperBound: 4, probabilityAtLeastOne: 0.91,
                liveWeight: 0.4, evidenceTier: .liveInformed, horizonMinutes: 60, modelVersion: "fresh-v2",
                validation: validation, abstentionReason: nil
            ),
            available: 4,
            total: 7
        )
        future.isSuggested = true

        let option = ParkingOption.onStreet(
            future,
            plan: ParkingPlan(arrival: .now.addingTimeInterval(3_600), duration: .oneHour)
        )
        let spoken = SuggestedOnStreetAreaButton.accessibilityText(for: option)

        XCTAssertEqual(future.available, 4)
        XCTAssertEqual(option.classification, .predicted)
        XCTAssertEqual(option.available, 2)
        XCTAssertEqual(option.pinLabel, "~2")
        XCTAssertEqual(option.availabilityLabel, "About 2 of 7 typically available")
        XCTAssertNotEqual(option.pinLabel, "\(future.available)")
        XCTAssertFalse(option.availabilityLabel.contains("available now"))
        XCTAssertFalse(spoken.contains("4 of 7"))
        XCTAssertEqual(
            spoken,
            "Suggested street parking, Collins Street, About 2 of 7 typically available. This is a suggestion, not a guarantee."
        )
    }

    func testUnknownOptionKindUsesParkingLabelInsteadOfUnknown() {
        XCTAssertEqual(ParkingOptionKind(StaticParkingKind.unknown), .unknown)
        XCTAssertEqual(ParkingOptionKind.unknown.rawValue, "Parking")
        XCTAssertEqual(ParkingOptionKind.unknown.rawValue.uppercased(), "PARKING")
        XCTAssertEqual(ParkingOptionKind.onStreet.rawValue, "On-street")
        XCTAssertEqual(ParkingOptionKind.offStreet.rawValue, "Off-street")
        XCTAssertEqual(ParkingOptionKind(StaticParkingKind.onStreet), .onStreet)
        XCTAssertEqual(ParkingOptionKind(StaticParkingKind.offStreet), .offStreet)
    }

    func testOptionLocationLabelFallsBackAndDeduplicatesLocality() {
        let glenWaverley = staticLocation(municipality: "Monash", locality: "Glen Waverley")
        XCTAssertEqual(glenWaverley.locationLabel, "Glen Waverley, Monash")
        XCTAssertEqual(staticLocation(municipality: "Ballarat", locality: nil).locationLabel, "Ballarat")
        XCTAssertEqual(staticLocation(municipality: "Ballarat", locality: "").locationLabel, "Ballarat")
        XCTAssertEqual(staticLocation(municipality: "Wyndham", locality: "   ").locationLabel, "Wyndham")
        XCTAssertEqual(staticLocation(municipality: "Hamilton", locality: "Hamilton").locationLabel, "Hamilton")
        XCTAssertEqual(staticLocation(municipality: "Casey", locality: "casey").locationLabel, "Casey")
        XCTAssertEqual(glenWaverley.name, "Fixture parking")
        XCTAssertEqual(glenWaverley.source.name, "Fixture Council")
        XCTAssertEqual(glenWaverley.kind, .offStreet)
        XCTAssertEqual(glenWaverley.classification, .staticOnly)
        XCTAssertEqual(glenWaverley.municipality, "Monash")
    }

    func testUnknownDetailDisclaimerStaysNeutral() {
        let unknown = ZoneDetailDisclaimer.detail(for: .unknown)
        XCTAssertTrue(unknown.localizedCaseInsensitiveContains("location"))
        XCTAssertTrue(unknown.localizedCaseInsensitiveContains("accessibility"))
        XCTAssertTrue(unknown.localizedCaseInsensitiveContains("posted signs or facility information"))
        XCTAssertFalse(unknown.localizedCaseInsensitiveContains("facility hours"))
        XCTAssertFalse(unknown.localizedCaseInsensitiveContains("sensor"))
        XCTAssertEqual(
            ZoneDetailDisclaimer.detail(for: .onStreet),
            "Counts and estimates can change. Check the sign and meter before you leave the car. Sensors can misread on public holidays and near construction."
        )
        XCTAssertEqual(
            ZoneDetailDisclaimer.detail(for: .offStreet),
            "Facility hours, spaces and prices are controlled by the provider. Check before you travel."
        )
    }

    private func option(classification: ParkingDataClassification, available: Int?, total: Int?) -> ParkingOption {
        ParkingOption(
            id: "fixture", kind: .offStreet, title: "Fixture parking", locationLabel: "Fixture Council",
            coordinate: .melbourneCBD, availabilityState: .unknown, available: available, total: total,
            restrictionLabel: "2P until 5:30 pm", restrictionWindow: "Active now", activeNow: true,
            price: .init(primaryText: "$3.60/hr", detail: "Official tariff", provider: "Fixture Council", actionLabel: nil, actionURL: nil),
            provider: "Fixture Council", sourceTimestamp: nil,
            proximity: ParkingProximity(
                straightLineMetres: 100,
                reference: .init(coordinate: .melbourneCBD, label: "Test destination")
            ),
            prediction: nil,
            isSuggested: false, zoneNumber: nil, classification: classification,
            warningText: classification == .verifiedLive ? nil : "Not live",
            sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: [], clusterCount: nil, clusterViewport: nil
        )
    }

    private func staticLocation(municipality: String, locality: String?) -> StaticParkingLocation {
        StaticParkingLocation(
            id: "fixture", name: "Fixture parking", municipality: municipality, locality: locality,
            coordinate: .melbourneCBD, kind: .offStreet, archetype: .general, capacity: 40, accessibleSpaces: nil,
            schedules: [], tariffs: [],
            source: .init(
                id: "fixture", name: "Fixture Council", sourceURL: URL(string: "https://example.com")!,
                licenseName: "Official", licenseURL: nil, datasetUpdatedAt: nil,
                checkedAt: Date(timeIntervalSince1970: 1_777_000_000)
            ),
            classification: .staticOnly, predictionEvidence: nil
        )
    }

    private func zone(
        prediction: AvailabilityPrediction,
        available: Int = 7,
        total: Int = 10
    ) -> ParkingZone {
        ParkingZone(
            zoneNumber: 7001,
            metadata: ZoneMetadata(
                zoneNumber: 7001, streetName: "Collins Street", fromStreet: "Swanston Street",
                toStreet: "Russell Street", coordinate: .melbourneCBD, sensorCount: 10
            ),
            available: available, total: total, restrictionLabel: "Up to 2 hours", payment: .paid,
            prediction: prediction,
            proximity: ParkingProximity(
                straightLineMetres: 120,
                reference: .init(coordinate: .melbourneCBD, label: "Test destination")
            ),
            newestTimestamp: .now, mode: .live,
            schedule: [], isSuggested: false
        )
    }

    private func plan(hour: Int, minute: Int = 0, durationMinutes: Int) -> ParkingPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let arrival = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: hour, minute: minute))!
        return ParkingPlan(arrival: arrival, durationMinutes: durationMinutes)
    }
}

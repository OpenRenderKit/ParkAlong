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

    private func option(classification: ParkingDataClassification, available: Int?, total: Int?) -> ParkingOption {
        ParkingOption(
            id: "fixture", kind: .offStreet, title: "Fixture parking", locationLabel: "Fixture Council",
            coordinate: .melbourneCBD, availabilityState: .unknown, available: available, total: total,
            restrictionLabel: "2P until 5:30 pm", restrictionWindow: "Active now", activeNow: true,
            price: .init(primaryText: "$3.60/hr", detail: "Official tariff", provider: "Fixture Council", actionLabel: nil, actionURL: nil),
            provider: "Fixture Council", sourceTimestamp: nil, walkingMetres: 100, prediction: nil,
            isBestBet: false, zoneNumber: nil, classification: classification,
            warningText: classification == .verifiedLive ? nil : "Not live",
            sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: [], clusterCount: nil, clusterViewport: nil
        )
    }

    private func zone(prediction: AvailabilityPrediction) -> ParkingZone {
        ParkingZone(
            zoneNumber: 7001,
            metadata: ZoneMetadata(
                zoneNumber: 7001, streetName: "Collins Street", fromStreet: "Swanston Street",
                toStreet: "Russell Street", coordinate: .melbourneCBD, sensorCount: 10
            ),
            available: 7, total: 10, restrictionLabel: "Up to 2 hours", payment: .paid,
            prediction: prediction, walkingMetres: 120, newestTimestamp: .now, mode: .live,
            schedule: [], isBestBet: false
        )
    }

    private func plan(hour: Int, minute: Int = 0, durationMinutes: Int) -> ParkingPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let arrival = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: hour, minute: minute))!
        return ParkingPlan(arrival: arrival, durationMinutes: durationMinutes)
    }
}

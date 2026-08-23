import XCTest
@testable import ParkAlong

final class ParkingOptionTests: XCTestCase {
    func testFreeRestrictionProducesAuthoritativeFreePrice() {
        let price = ParkingPriceEngine.price(payment: .free, duration: .oneHour)
        XCTAssertEqual(price.primaryText, "Free")
        XCTAssertNil(price.actionURL)
    }

    func testPaidFifteenMinuteStayUsesCurrentCityFreeSessionPolicy() {
        let price = ParkingPriceEngine.price(payment: .paid, duration: .fifteenMinutes)
        XCTAssertEqual(price.primaryText, "$0 first 15 min")
        XCTAssertEqual(price.provider, "City of Melbourne · EasyPark")
        XCTAssertNotNil(price.actionURL)
    }

    func testPaidLongerStayDoesNotFabricateRate() {
        let price = ParkingPriceEngine.price(payment: .paid, duration: .twoHours)
        XCTAssertEqual(price.primaryText, "Check current price")
        XCTAssertEqual(price.actionLabel, "Check price with provider")
        XCTAssertFalse(price.primaryText.contains("$7"))
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

    private func option(classification: ParkingDataClassification, available: Int?, total: Int?) -> ParkingOption {
        ParkingOption(
            id: "fixture", kind: .offStreet, title: "Fixture parking", locationLabel: "Fixture Council",
            coordinate: .melbourneCBD, availabilityState: .unknown, available: available, total: total,
            restrictionLabel: "2P until 5:30 pm", restrictionWindow: "Active now", activeNow: true,
            price: .init(primaryText: "$3.60/hr", detail: "Official tariff", provider: "Fixture Council", actionLabel: nil, actionURL: nil),
            provider: "Fixture Council", sourceTimestamp: nil, walkingMetres: 100, prediction: nil,
            isBestBet: false, zoneNumber: nil, classification: classification,
            warningText: classification == .verifiedLive ? nil : "Not live",
            sourceDatasetAt: nil, sourceCheckedAt: nil
        )
    }
}

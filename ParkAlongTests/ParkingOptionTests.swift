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
}

import XCTest

@MainActor
final class ParkAlongUITests: XCTestCase {
    private func launch(_ arguments: [String] = ["-fixture-live"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-intercept-navigation"] + arguments
        app.launch()
        return app
    }

    func testPermissionDeniedKeepsDefaultCBDUsable() {
        let app = launch(["-fixture-live", "-location-denied"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.buttons["best-bet-button"].exists)
    }

    func testSearchChangesDestination() {
        let app = launch()
        app.buttons["destination-search-button"].tap()
        let field = app.textFields["destination-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Flinders")
        app.buttons["search-result-flinders"].tap()
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Flinders Street Station")
    }

    func testDurationAndZoneDetailNavigationHandoff() {
        let app = launch()
        app.buttons["duration-2h"].tap()
        XCTAssertEqual(app.buttons["duration-2h"].value as? String, "selected")
        app.buttons["best-bet-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["zone-availability"].label.contains("available"))
        app.buttons["navigate-button"].tap()
        XCTAssertTrue(app.staticTexts["navigation-intercepted"].waitForExistence(timeout: 2))
    }

    func testMoreStayDurationsSelectExactLongStay() {
        let app = launch()
        let more = app.buttons["duration-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 2))

        more.tap()
        let fourHours = app.buttons["duration-4h"]
        XCTAssertTrue(fourHours.waitForExistence(timeout: 2))
        fourHours.tap()

        XCTAssertEqual(more.label, "4 hours")
        XCTAssertEqual(more.value as? String, "selected")
    }

    func testAboutStartsWithVisualMarkerLegend() {
        let app = launch()
        app.buttons["About ParkAlong"].tap()

        for label in [
            "Available, verified live",
            "Limited, verified live",
            "Full, verified live",
            "Estimate, not live",
            "Location only, not live"
        ] {
            XCTAssertTrue(app.descendants(matching: .any)[label].waitForExistence(timeout: 2), label)
        }
    }

    func testErrorStateHasRetry() {
        let app = launch(["-fixture-error"])
        XCTAssertTrue(app.staticTexts["availability-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["retry-button"].exists)
    }

    func testLiveFailureKeepsMappedParkingWithWarning() {
        let app = launch(["-fixture-live-error"])
        let pin = app.buttons["static-pin-static-fixture-ballarat"]

        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        XCTAssertTrue(pin.label.localizedCaseInsensitiveContains("not live"))
        XCTAssertFalse(app.staticTexts["availability-error"].exists)
    }

    func testLoadingStateIsExplicit() {
        let app = launch(["-fixture-loading"])
        XCTAssertTrue(app.descendants(matching: .any)["availability-loading"].waitForExistence(timeout: 2))
    }

    func testStaticLocationPinShowsWarningRuleAndVerifiedPrice() {
        let app = launch()
        let pin = app.buttons["static-pin-static-fixture-ballarat"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        XCTAssertTrue(pin.label.localizedCaseInsensitiveContains("location only"))
        pin.tap()

        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["zone-availability"].label, "Availability unknown")
        XCTAssertTrue(app.staticTexts["data-quality-warning"].label.localizedCaseInsensitiveContains("not live"))
        XCTAssertTrue(app.staticTexts["zone-time-limit"].label.contains("until"))
        XCTAssertTrue(app.staticTexts["zone-price"].label.contains("$"))
    }

    func testLiveZoneDetailOmitsDataQualityWarning() {
        let app = launch()
        app.buttons["best-bet-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["data-quality-warning"].exists)
        XCTAssertTrue(app.staticTexts["zone-availability"].label.contains("available"))
    }
}

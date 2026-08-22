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

    func testErrorStateHasRetry() {
        let app = launch(["-fixture-error"])
        XCTAssertTrue(app.staticTexts["availability-error"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["retry-button"].exists)
    }

    func testLoadingStateIsExplicit() {
        let app = launch(["-fixture-loading"])
        XCTAssertTrue(app.descendants(matching: .any)["availability-loading"].waitForExistence(timeout: 2))
    }
}

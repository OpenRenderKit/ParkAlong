import XCTest

@MainActor
final class ParkAlongUITests: XCTestCase {
    private func launch(_ arguments: [String] = ["-fixture-live"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-intercept-navigation"] + arguments
        app.launch()
        return app
    }

    private func waitForValue(_ value: String, on element: XCUIElement, timeout: TimeInterval = 2) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func testPermissionDeniedKeepsDefaultCBDUsable() {
        let app = launch(["-fixture-live", "-location-denied"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.buttons["best-bet-button"].exists)
    }

    func testPrimaryMapActionsRemainDiscoverableInAdaptiveChrome() {
        let app = launch()

        XCTAssertTrue(app.otherElements["destination-search-container"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["destination-search-button"].exists)
        XCTAssertTrue(app.buttons["current-location-button"].exists)
        XCTAssertTrue(app.otherElements["parking-action-dock"].exists)
        XCTAssertTrue(app.buttons["About ParkAlong"].exists)
        XCTAssertTrue(app.buttons["refresh-availability-button"].exists)
    }

    func testStayTrackExposesEveryPresetAndOpensPlanner() {
        let app = launch()
        XCTAssertTrue(element("stay-duration-track", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["duration-more"].exists)

        for identifier in ["duration-15m", "duration-1h", "duration-2h", "duration-3h", "duration-4h", "duration-6h", "duration-8h+"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 2), identifier)
        }

        app.buttons["duration-8h+"].tap()
        XCTAssertTrue(element("arrival-stay-planner", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["planner-arrival-tomorrow"].exists)
        XCTAssertTrue(app.buttons["planner-apply"].exists)
        XCTAssertTrue(element("planner-arrival-context", in: app).exists)
    }

    func testPlannerAppliesFutureCustomStay() {
        let app = launch()
        XCTAssertTrue(element("stay-duration-track", in: app).waitForExistence(timeout: 3))
        let eightHoursPlus = app.buttons["duration-8h+"]
        XCTAssertTrue(eightHoursPlus.waitForExistence(timeout: 2))
        eightHoursPlus.tap()
        XCTAssertTrue(element("arrival-stay-planner", in: app).waitForExistence(timeout: 2))

        app.buttons["planner-arrival-tomorrow"].tap()
        let twelveHours = app.buttons["planner-duration-720"]
        XCTAssertTrue(twelveHours.waitForExistence(timeout: 2))
        twelveHours.tap()

        app.buttons["planner-apply"].tap()
        XCTAssertTrue(app.buttons["duration-8h+"].waitForExistence(timeout: 2))
        waitForValue("selected", on: app.buttons["duration-8h+"])
        XCTAssertTrue(element("planned-arrival-caption", in: app).waitForExistence(timeout: 2))
    }

    func testPlannerButtonOpensArrivalStaySheet() {
        let app = launch()
        XCTAssertTrue(app.buttons["arrival-planner-button"].waitForExistence(timeout: 2))
        app.buttons["arrival-planner-button"].tap()
        XCTAssertTrue(element("arrival-stay-planner", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["planner-reset"].exists)
    }

    func testSearchChangesDestination() {
        let app = launch()
        app.buttons["destination-search-button"].tap()
        let field = app.textFields["destination-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        XCTAssertTrue(element("search-results-container", in: app).waitForExistence(timeout: 2))
        field.tap()
        field.typeText("Flinders")
        XCTAssertTrue(app.buttons["search-result-flinders"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("search-result-kind-place", in: app).exists)
        app.buttons["search-result-flinders"].tap()
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Flinders Street Station")
    }

    func testSearchIdleStateAvoidsEmptyBlackScreen() {
        let app = launch()
        XCTAssertTrue(app.buttons["destination-search-button"].waitForExistence(timeout: 3))
        app.buttons["destination-search-button"].tap()
        XCTAssertTrue(element("search-results-container", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["search-current-location"].exists)
        XCTAssertTrue(app.buttons["search-this-area"].exists)
        let idle = element("search-idle", in: app)
        XCTAssertTrue(idle.waitForExistence(timeout: 2))
        XCTAssertFalse(idle.label.localizedCaseInsensitiveContains("melbourne"))
        XCTAssertTrue(idle.label.localizedCaseInsensitiveContains("place") || idle.label.localizedCaseInsensitiveContains("parking"))
    }

    func testDurationAndZoneDetailNavigationHandoff() {
        let app = launch()
        app.buttons["duration-2h"].tap()
        waitForValue("selected", on: app.buttons["duration-2h"])
        app.buttons["best-bet-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["zone-availability"].label.contains("available"))
        XCTAssertTrue(app.buttons["navigate-button"].isHittable)
        app.buttons["navigate-button"].tap()
        XCTAssertTrue(app.staticTexts["navigation-intercepted"].waitForExistence(timeout: 2))
    }

    func testStayTrackSelectsExactLongStayWithoutMoreMenu() {
        let app = launch()
        let fourHours = app.buttons["duration-4h"]
        XCTAssertTrue(fourHours.waitForExistence(timeout: 2))
        fourHours.tap()

        waitForValue("selected", on: fourHours)
        XCTAssertFalse(app.buttons["duration-more"].exists)
    }

    func testTimeLimitExplorerShowsWeeklySchedule() {
        let app = launch()
        app.buttons["best-bet-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))

        let timeLimitRow = app.buttons["zone-time-limit-row"]
        XCTAssertTrue(timeLimitRow.waitForExistence(timeout: 2))
        timeLimitRow.tap()

        XCTAssertTrue(element("schedule-explorer", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["schedule-day-0"].exists)
        XCTAssertTrue(element("schedule-arrival-context", in: app).exists)
        XCTAssertTrue(element("schedule-day-strip", in: app).exists)
    }

    func testAboutStartsWithVisualMarkerLegend() {
        let app = launch()
        app.buttons["About ParkAlong"].tap()

        XCTAssertTrue(element("about-legend", in: app).waitForExistence(timeout: 2))
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
        XCTAssertTrue(app.buttons["refresh-availability-button"].exists)
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
        let timeLimit = element("zone-time-limit", in: app)
        XCTAssertTrue(timeLimit.waitForExistence(timeout: 2))
        XCTAssertTrue(timeLimit.label.contains("until") || timeLimit.label.lowercased().contains("stay") || timeLimit.label.lowercased().contains("signed"))
        XCTAssertTrue(app.staticTexts["zone-price"].label.contains("$"))
        XCTAssertTrue(app.buttons["navigate-button"].isHittable)
    }

    func testLiveZoneDetailOmitsDataQualityWarning() {
        let app = launch()
        app.buttons["best-bet-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["data-quality-warning"].exists)
        XCTAssertTrue(app.staticTexts["zone-availability"].label.contains("available"))
        XCTAssertTrue(element("forecast-evidence", in: app).waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Measured probability")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Confidence")).firstMatch.exists)
        let probability = element("forecast-probability", in: app)
        if probability.exists {
            XCTAssertTrue(probability.label.localizedCaseInsensitiveContains("Modelled chance"))
        }
        XCTAssertTrue(app.buttons["navigate-button"].isHittable)
    }
}

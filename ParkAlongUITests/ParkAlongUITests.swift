import XCTest

@MainActor
final class ParkAlongUITests: XCTestCase {
    private func launch(_ arguments: [String] = ["-fixture-live"]) -> XCUIApplication {
        let app = makeApp(arguments)
        app.launch()
        return app
    }

    private func waitForValue(_ value: String, on element: XCUIElement, timeout: TimeInterval = 2) {
        let predicate = NSPredicate { _, _ in
            element.value as? String == value || (value == "selected" && element.isSelected)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func makeApp(_ arguments: [String] = ["-fixture-live"]) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = ["-ui-testing", "-intercept-navigation"] + arguments
        if !arguments.contains("-UIPreferredContentSizeCategoryName") {
            // The simulator retains this preference between processes. Reset it
            // so the dedicated accessibility test cannot leak into later cases.
            launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryL"
            ]
        }
        app.launchArguments = launchArguments
        return app
    }

    private func staticMarkers(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "static-pin-")
        )
    }

    private func waitForDenseMapReady(_ app: XCUIApplication) -> XCUIElementQuery {
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        let markers = staticMarkers(in: app)
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 5))
        return markers
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 2) {
        let predicate = NSPredicate { _, _ in
            !element.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }

    private func printTapToZoneDetailSheetSamples(_ samples: [Duration]) {
        let values = samples.map(milliseconds(from:))
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        let median = sorted[sorted.count / 2]
        let summary = values.map { String(format: "%.1f", $0) }.joined(separator: ",")
        print(
            "tap-to-zone-detail-sheet-ms samples=[\(summary)] mean=\(String(format: "%.1f", mean)) median=\(String(format: "%.1f", median)) min=\(String(format: "%.1f", sorted.first ?? 0)) max=\(String(format: "%.1f", sorted.last ?? 0))"
        )
    }

    private func performanceMeasureOptions(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func openPlanner(in app: XCUIApplication) {
        let plannerButton = app.buttons["arrival-planner-button"]
        XCTAssertTrue(plannerButton.waitForExistence(timeout: 2))
        plannerButton.tap()
        waitForPlannerReady(in: app)
    }

    private func waitForPlannerReady(in app: XCUIApplication, timeout: TimeInterval = 8) {
        XCTAssertTrue(element("arrival-stay-planner", in: app).waitForExistence(timeout: timeout))
        let reset = app.buttons["planner-reset"]
        let predicate = NSPredicate { _, _ in
            reset.exists && reset.isHittable
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: reset)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func revealPlannerElement(_ identifier: String, in app: XCUIApplication) {
        let control = element(identifier, in: app)
        if control.exists { return }
        element("arrival-stay-planner", in: app).swipeUp()
        if control.exists { return }
        app.swipeUp()
    }

    private func tapPlannerControl(_ identifier: String, in app: XCUIApplication) {
        revealPlannerElement(identifier, in: app)
        let control = element(identifier, in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 2), identifier)
        if !control.isHittable {
            element("arrival-stay-planner", in: app).swipeUp()
        }
        if !control.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(control.isHittable, identifier)
        control.tap()
    }

    private func chooseTomorrowStay(minutes: Int, in app: XCUIApplication) {
        app.buttons["planner-arrival-tomorrow"].tap()
        tapPlannerControl("planner-duration-\(minutes)", in: app)
    }

    private func assertPlannerOvernightSummary(in app: XCUIApplication) {
        revealPlannerElement("planner-overnight-summary", in: app)
        XCTAssertTrue(element("planner-overnight-summary", in: app).waitForExistence(timeout: 2))
    }

    private func assertMapReplacedByPlanner(in app: XCUIApplication) {
        XCTAssertFalse(element("parking-map", in: app).exists)
        XCTAssertFalse(app.maps.firstMatch.exists)
    }

    private func assertPlannerDismissed(in app: XCUIApplication) {
        XCTAssertFalse(element("arrival-stay-planner", in: app).waitForExistence(timeout: 1))
        XCTAssertTrue(element("parking-map", in: app).waitForExistence(timeout: 2))
    }

    func testPermissionDeniedKeepsDefaultCBDUsable() {
        let app = launch(["-fixture-live", "-location-denied"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.buttons["suggested-on-street-area-button"].exists)

        let recovery = element("location-settings-recovery", in: app)
        XCTAssertTrue(recovery.waitForExistence(timeout: 3))
        let message = element("location-denied-status", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        XCTAssertTrue(
            message.label.localizedCaseInsensitiveContains("Melbourne CBD"),
            message.label
        )
        XCTAssertTrue(
            message.label.localizedCaseInsensitiveContains("can’t use your location")
                || message.label.localizedCaseInsensitiveContains("can't use your location"),
            message.label
        )
        let openSettings = app.buttons["open-location-settings-button"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 2))
        XCTAssertTrue(openSettings.isHittable)
        XCTAssertEqual(openSettings.label, "Open Settings")
        XCTAssertTrue(app.buttons["current-location-button"].exists)
    }

    func testAuthorizedStartupCentersOnCurrentLocation() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Current location")
        waitForValue("selected", on: app.buttons["current-location-button"])
        XCTAssertTrue(element("map-compass-scale", in: app).waitForExistence(timeout: 3))
    }

    func testRestrictedLocationFallsBackWithoutHanging() {
        let app = launch(["-fixture-live", "-location-restricted"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.staticTexts["Location access restricted"].exists)
        XCTAssertFalse(app.buttons["open-location-settings-button"].exists)
    }

    func testLocationTimeoutFallsBackWithoutHanging() {
        let app = launch(["-fixture-live", "-location-timeout"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.staticTexts["Current location timed out"].exists)
        XCTAssertFalse(app.buttons["open-location-settings-button"].exists)
    }

    func testUnavailableLocationFallsBackWithoutHanging() {
        let app = launch(["-fixture-live", "-location-unavailable"])
        XCTAssertTrue(app.staticTexts["destination-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["destination-title"].label, "Melbourne CBD")
        XCTAssertTrue(app.staticTexts["Current location unavailable"].exists)
        XCTAssertFalse(app.buttons["open-location-settings-button"].exists)
    }

    func testDenseMarkerMapAcceptsPinchAndRemainsInteractive() {
        let app = launch(["-fixture-live", "-fixture-dense"])
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 3))

        map.pinch(withScale: 0.55, velocity: -2)

        XCTAssertTrue(map.exists)
        XCTAssertTrue(map.isHittable)
        let markers = staticMarkers(in: app)
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(markers.count, 0)
        XCTAssertLessThanOrEqual(markers.count, 48)
        XCTAssertTrue(markers.firstMatch.isHittable)
        markers.firstMatch.tap()
        let detailSheet = app.otherElements["zone-detail-sheet"]
        XCTAssertTrue(detailSheet.waitForExistence(timeout: 2))
        detailSheet.swipeDown()
        waitUntilGone(detailSheet)
        let twoHours = app.buttons["duration-2h"]
        XCTAssertTrue(twoHours.isHittable)
        twoHours.tap()
        waitForValue("selected", on: twoHours)
    }

    func testClusterTapLandsOnVisibleParkingChildren() {
        let app = launch(["-fixture-live", "-fixture-cluster"])
        let cluster = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "parking locations in this area")
        ).firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 3))

        cluster.tap()

        let child = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "static-pin-static-fixture-cluster-", "location only")
        ).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 4))
        XCTAssertTrue(child.isHittable)
        XCTAssertFalse(cluster.exists)
    }

    func testDenseMapLaunchToMarkerReadinessPerformance() {
        let app = makeApp(["-fixture-live", "-fixture-dense"])
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
            options: performanceMeasureOptions(iterations: 3)
        ) {
            app.launch()
            _ = waitForDenseMapReady(app)
            app.terminate()
        }
    }

    func testDenseMapPinchResponsivenessPerformance() {
        let app = launch(["-fixture-live", "-fixture-dense"])
        let map = app.maps.firstMatch
        _ = waitForDenseMapReady(app)

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
            options: performanceMeasureOptions(iterations: 3)
        ) {
            map.pinch(withScale: 0.55, velocity: -2)
            map.pinch(withScale: 1.8, velocity: 2)
            XCTAssertTrue(map.exists)
            XCTAssertTrue(map.isHittable)
        }
    }

    func testDenseMarkerSelectionWorkflowPerformance() {
        let app = launch(["-fixture-live", "-fixture-dense"])
        let markers = waitForDenseMapReady(app)
        let detailSheet = app.otherElements["zone-detail-sheet"]
        let clock = ContinuousClock()
        var tapToSheetSamples: [Duration] = []

        for _ in 0..<3 {
            XCTAssertTrue(markers.firstMatch.isHittable)
            let started = clock.now
            markers.firstMatch.tap()
            XCTAssertTrue(detailSheet.waitForExistence(timeout: 2))
            tapToSheetSamples.append(clock.now - started)
            detailSheet.swipeDown()
            waitUntilGone(detailSheet)
        }
        printTapToZoneDetailSheetSamples(tapToSheetSamples)

        measure(
            metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
            options: performanceMeasureOptions(iterations: 3)
        ) {
            XCTAssertTrue(markers.firstMatch.isHittable)
            markers.firstMatch.tap()
            XCTAssertTrue(detailSheet.waitForExistence(timeout: 2))
            detailSheet.swipeDown()
            waitUntilGone(detailSheet)
        }
    }

    func testStayTrackRemainsUsableAtAccessibilityTextSize() {
        let app = launch([
            "-fixture-live",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ])
        let track = element("stay-duration-track", in: app)
        XCTAssertTrue(track.waitForExistence(timeout: 3))
        let fifteenMinutes = app.buttons["duration-15m"]
        XCTAssertTrue(fifteenMinutes.waitForExistence(timeout: 2))
        XCTAssertTrue(fifteenMinutes.isHittable)
        fifteenMinutes.tap()
        waitForValue("selected", on: fifteenMinutes)
    }

    func testStayDurationUsesNativeSegmentedControl() {
        let app = launch()
        let picker = app.segmentedControls["stay-duration-picker"]

        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertEqual(picker.buttons.count, 7)
    }

    func testStayDurationSegmentsHaveFullHeightTargetsAndAcceptAdjacentSelections() {
        let app = launch()
        XCTAssertTrue(app.segmentedControls["stay-duration-picker"].waitForExistence(timeout: 3))

        for identifier in ["duration-3h", "duration-4h", "duration-6h"] {
            XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height, 44, identifier)
        }

        for (identifier, statusText) in [
            ("duration-3h", "3-hour stay"),
            ("duration-4h", "4-hour stay"),
            ("duration-6h", "6-hour stay")
        ] {
            let segment = app.buttons[identifier]
            XCTAssertTrue(segment.isHittable, identifier)
            segment.tap()
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS[c] %@", statusText),
                object: app.staticTexts["availability-status"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, identifier)
        }
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

    func testStayTrackExposesEveryPresetAndEightHoursDoesNotOpenPlanner() {
        let app = launch()
        XCTAssertTrue(element("stay-duration-track", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["duration-more"].exists)

        for identifier in ["duration-15m", "duration-1h", "duration-2h", "duration-3h", "duration-4h", "duration-6h", "duration-8h+"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 2), identifier)
        }

        app.buttons["duration-8h+"].tap()
        waitForValue("selected", on: app.buttons["duration-8h+"])
        XCTAssertFalse(element("arrival-stay-planner", in: app).exists)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", "8-hour stay"),
            object: app.staticTexts["availability-status"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    func testPlannerAppliesFutureCustomStay() {
        let app = launch()
        XCTAssertTrue(element("stay-duration-track", in: app).waitForExistence(timeout: 3))
        openPlanner(in: app)
        assertMapReplacedByPlanner(in: app)

        chooseTomorrowStay(minutes: 720, in: app)

        app.buttons["planner-apply"].tap()
        assertPlannerDismissed(in: app)
        XCTAssertTrue(app.buttons["duration-8h+"].waitForExistence(timeout: 2))
        waitForValue("selected", on: app.buttons["duration-8h+"])
        XCTAssertTrue(element("planned-arrival-caption", in: app).waitForExistence(timeout: 2))
    }

    func testPlannerOpensFullScreenArrivalStayPlanner() {
        let app = launch()
        openPlanner(in: app)
        assertMapReplacedByPlanner(in: app)
    }

    func testPlannerOpensAndCloseDiscardsDraft() {
        let app = launch()
        openPlanner(in: app)

        XCTAssertTrue(element("planner-arrival-context", in: app).exists)
        XCTAssertTrue(app.buttons["planner-arrival-today"].exists)
        XCTAssertTrue(app.buttons["planner-arrival-tomorrow"].exists)
        XCTAssertTrue(element("planner-arrival-date", in: app).exists)
        XCTAssertTrue(app.buttons["planner-close"].exists)
        XCTAssertTrue(app.buttons["planner-apply"].exists)
        XCTAssertTrue(element("planner-duration-days", in: app).exists)
        XCTAssertTrue(element("planner-duration-hours", in: app).exists)
        XCTAssertTrue(element("planner-duration-minutes", in: app).exists)
        for minutes in [15, 60, 120, 180, 240, 360, 480, 720, 1440, 2880, 10080] {
            XCTAssertTrue(app.buttons["planner-duration-\(minutes)"].exists, "planner-duration-\(minutes)")
        }
        assertMapReplacedByPlanner(in: app)

        chooseTomorrowStay(minutes: 1440, in: app)
        assertPlannerOvernightSummary(in: app)

        app.buttons["planner-close"].tap()
        assertPlannerDismissed(in: app)
        XCTAssertTrue(app.buttons["duration-1h"].waitForExistence(timeout: 2))
        waitForValue("selected", on: app.buttons["duration-1h"])
        XCTAssertFalse(element("planned-arrival-caption", in: app).exists)
    }

    func testPlannerResetAppliesLiveOneHourStay() {
        let app = launch()
        let twoHours = app.buttons["duration-2h"]
        XCTAssertTrue(twoHours.waitForExistence(timeout: 3))
        twoHours.tap()
        waitForValue("selected", on: twoHours)

        openPlanner(in: app)
        chooseTomorrowStay(minutes: 720, in: app)
        app.buttons["planner-reset"].tap()

        assertPlannerDismissed(in: app)
        XCTAssertTrue(app.buttons["duration-1h"].waitForExistence(timeout: 2))
        waitForValue("selected", on: app.buttons["duration-1h"])
        XCTAssertFalse(element("planned-arrival-caption", in: app).exists)
    }

    func testPlannerApplyCommitsArrivalAndDuration() {
        let app = launch()
        openPlanner(in: app)
        chooseTomorrowStay(minutes: 1440, in: app)
        assertPlannerOvernightSummary(in: app)

        app.buttons["planner-apply"].tap()
        assertPlannerDismissed(in: app)
        XCTAssertTrue(app.buttons["duration-8h+"].waitForExistence(timeout: 2))
        waitForValue("selected", on: app.buttons["duration-8h+"])
        XCTAssertTrue(element("planned-arrival-caption", in: app).waitForExistence(timeout: 2))
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

    func testBundledCatalogSearchFindsRepresentativeMelbourneLocalities() {
        let app = launch(["-fixture-live", "-fixture-real-static-catalog"])
        let localities = [
            "Burwood", "Kew", "Glen Waverley", "Tarneit", "South Yarra",
            "Elsternwick", "Box Hill", "Clayton", "Springvale"
        ]

        for locality in localities {
            app.buttons["destination-search-button"].tap()
            let field = app.textFields["destination-search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 2), locality)
            field.tap()
            field.typeText(locality)

            let result = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "search-result-parking-")
            ).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), locality)
            XCTAssertTrue(result.label.localizedCaseInsensitiveContains(locality), result.label)

            result.tap()
            let detailSheet = app.otherElements["zone-detail-sheet"]
            XCTAssertTrue(detailSheet.waitForExistence(timeout: 3), locality)
            let localityLabel = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", locality)
            ).firstMatch
            XCTAssertTrue(localityLabel.waitForExistence(timeout: 2), locality)
            detailSheet.swipeDown()
            XCTAssertTrue(app.buttons["destination-search-button"].waitForExistence(timeout: 2), locality)
        }
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
        app.buttons["suggested-on-street-area-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["zone-availability"].label.contains("available"))
        let navigate = app.buttons["navigate-button"]
        XCTAssertTrue(navigate.isHittable)
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Drive"))
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Apple Maps"))
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Little Collins"))
        XCTAssertTrue(element("navigation-pin-caveat", in: app).waitForExistence(timeout: 2))
        navigate.tap()
        XCTAssertTrue(app.staticTexts["navigation-intercepted"].waitForExistence(timeout: 2))
    }

    func testStayTrackSelectsExactLongStayWithoutMoreMenu() {
        let app = launch()
        let fourHours = app.buttons["duration-4h"]
        XCTAssertTrue(fourHours.waitForExistence(timeout: 2))
        XCTAssertTrue(fourHours.isHittable)
        fourHours.tap()

        let fourHourStatus = app.staticTexts["availability-status"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", "4-hour stay"),
            object: fourHourStatus
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
        XCTAssertFalse(app.buttons["duration-more"].exists)
    }

    func testTimeLimitExplorerShowsWeeklySchedule() {
        let app = launch()
        app.buttons["suggested-on-street-area-button"].tap()
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
        let pin = element("static-pin-static-fixture-ballarat", in: app)

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
        let pin = element("static-pin-static-fixture-ballarat", in: app)
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
        let suggested = app.buttons["suggested-on-street-area-button"]
        XCTAssertTrue(suggested.waitForExistence(timeout: 3))
        XCTAssertTrue(suggested.label.localizedCaseInsensitiveContains("Suggested street parking"))
        suggested.tap()
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

        let explanation = element("suggestion-explanation", in: app)
        XCTAssertTrue(explanation.waitForExistence(timeout: 2))
        XCTAssertTrue(explanation.label.localizedCaseInsensitiveContains("Why this suggestion"), explanation.label)
        XCTAssertTrue(explanation.label.localizedCaseInsensitiveContains("street parking"), explanation.label)
        XCTAssertTrue(explanation.label.localizedCaseInsensitiveContains("straight-line"), explanation.label)
        XCTAssertTrue(
            explanation.label.localizedCaseInsensitiveContains("Current location")
                || explanation.label.localizedCaseInsensitiveContains("Melbourne CBD"),
            explanation.label
        )
        XCTAssertFalse(explanation.label.contains("%"), explanation.label)
        XCTAssertFalse(explanation.label.localizedCaseInsensitiveContains("score"), explanation.label)
        XCTAssertFalse(explanation.label.localizedCaseInsensitiveContains("guarantee"), explanation.label)
        XCTAssertFalse(explanation.label.localizedCaseInsensitiveContains("walk"), explanation.label)

        let proximity = element("straight-line-proximity", in: app)
        XCTAssertTrue(proximity.waitForExistence(timeout: 2))
        XCTAssertTrue(proximity.label.localizedCaseInsensitiveContains("Distance to"), proximity.label)
        XCTAssertTrue(proximity.label.localizedCaseInsensitiveContains("straight-line"), proximity.label)
        XCTAssertTrue(proximity.label.localizedCaseInsensitiveContains("walking route"), proximity.label)
        XCTAssertFalse(proximity.label.localizedCaseInsensitiveContains(" m walk"))
        XCTAssertFalse(proximity.label.localizedCaseInsensitiveContains("km walk"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", " m walk")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "km walk")).firstMatch.exists)

        let navigate = app.buttons["navigate-button"]
        XCTAssertTrue(navigate.isHittable)
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Drive to"))
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Apple Maps"))
        XCTAssertTrue(navigate.label.localizedCaseInsensitiveContains("Little Collins"))
        let pinCaveat = element("navigation-pin-caveat", in: app)
        XCTAssertTrue(pinCaveat.waitForExistence(timeout: 2))
        XCTAssertTrue(pinCaveat.label.localizedCaseInsensitiveContains("parking pin"))
        XCTAssertTrue(pinCaveat.label.localizedCaseInsensitiveContains("entrance"))
        XCTAssertFalse(pinCaveat.label.localizedCaseInsensitiveContains("walking"))
    }

    func testNavigateWithLiveActivityShowsSessionWithoutBlockingHandoff() {
        let app = launch()
        app.buttons["suggested-on-street-area-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        app.buttons["navigate-button"].tap()

        XCTAssertTrue(app.staticTexts["navigation-intercepted"].waitForExistence(timeout: 2))
        XCTAssertTrue(element("live-activity-status", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["live-activity-status"].label.localizedCaseInsensitiveContains("lock screen"))
        XCTAssertTrue(app.buttons["open-parking-session-button"].waitForExistence(timeout: 2))
        app.buttons["open-parking-session-button"].tap()

        XCTAssertTrue(element("parking-session-sheet", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["mark-parked-button"].waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(app.buttons["mark-parked-button"].frame.height, 44)
        XCTAssertTrue(app.switches["show-lock-screen-location-toggle"].exists)
        XCTAssertEqual(app.switches["show-lock-screen-location-toggle"].value as? String, "0")
        XCTAssertTrue(element("parking-session-availability", in: app).label.localizedCaseInsensitiveContains("observed"))
        XCTAssertFalse(element("parking-session-availability", in: app).label.localizedCaseInsensitiveContains("live"))
    }

    func testLiveActivityDisabledFallbackLetsUserParkAndEnd() {
        let app = launch(["-fixture-live", "-live-activity-disabled"])
        completeNavigateToSession(in: app)

        XCTAssertTrue(element("live-activity-fallback-status", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["live-activity-fallback-status"].label.localizedCaseInsensitiveContains("lock screen"))
        XCTAssertTrue(app.staticTexts["parking-session-title"].label.contains("Little Collins"))
        XCTAssertTrue(element("posted-signs-govern", in: app).waitForExistence(timeout: 2))

        app.buttons["mark-parked-button"].tap()
        XCTAssertTrue(app.buttons["return-to-car-button"].waitForExistence(timeout: 2))
        XCTAssertTrue(element("parking-session-countdown", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("parking-session-departure", in: app).label.localizedCaseInsensitiveContains("Leave by"))

        let privacy = app.switches["show-lock-screen-location-toggle"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 2))
        privacy.tap()
        waitForValue("1", on: privacy)

        app.buttons["set-reminder-button"].tap()
        XCTAssertTrue(element("parking-reminder-status", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("parking-reminder-status", in: app).label.localizedCaseInsensitiveContains("Reminder set"))

        app.buttons["return-to-car-button"].tap()
        XCTAssertTrue(element("return-navigation-intercepted", in: app).waitForExistence(timeout: 2))

        app.buttons["end-parking-button"].tap()
        XCTAssertFalse(element("parking-session-sheet", in: app).waitForExistence(timeout: 1))
        XCTAssertFalse(element("parking-session-chip", in: app).waitForExistence(timeout: 1))
    }

    func testLiveActivityUnavailableFallbackShowsSessionControls() {
        let app = launch(["-fixture-live", "-live-activity-unavailable"])
        completeNavigateToSession(in: app)

        XCTAssertTrue(element("live-activity-fallback-status", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["live-activity-fallback-status"].label.localizedCaseInsensitiveContains("isn’t available")
            || app.staticTexts["live-activity-fallback-status"].label.localizedCaseInsensitiveContains("isn't available")
            || app.staticTexts["live-activity-fallback-status"].label.localizedCaseInsensitiveContains("available"))
        XCTAssertTrue(app.buttons["mark-parked-button"].isHittable)
        XCTAssertTrue(app.buttons["end-parking-button"].isHittable)
        XCTAssertTrue(app.switches["show-lock-screen-location-toggle"].exists)
    }

    func testStaticParkingSessionSaysAvailabilityUnavailable() {
        let app = launch()
        let pin = element("static-pin-static-fixture-ballarat", in: app)
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        app.buttons["navigate-button"].tap()
        XCTAssertTrue(app.buttons["open-parking-session-button"].waitForExistence(timeout: 2))
        app.buttons["open-parking-session-button"].tap()

        XCTAssertTrue(element("parking-session-sheet", in: app).waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["parking-session-availability"].label, "Availability unavailable")
        XCTAssertTrue(app.staticTexts["parking-session-title"].label.contains("Sturt Street"))
    }

    private func completeNavigateToSession(in app: XCUIApplication) {
        app.buttons["suggested-on-street-area-button"].tap()
        XCTAssertTrue(app.otherElements["zone-detail-sheet"].waitForExistence(timeout: 2))
        app.buttons["navigate-button"].tap()
        XCTAssertTrue(app.staticTexts["navigation-intercepted"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["open-parking-session-button"].waitForExistence(timeout: 2))
        app.buttons["open-parking-session-button"].tap()
        XCTAssertTrue(element("parking-session-sheet", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["mark-parked-button"].waitForExistence(timeout: 2))
    }
}

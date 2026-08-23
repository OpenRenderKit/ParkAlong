import XCTest
@testable import ParkAlong

final class RestrictionEngineTests: XCTestCase {
    private let engine = RestrictionEngine(timeZone: TimeZone(identifier: "Australia/Melbourne")!)

    func testParsesPublicParkingCodesAndPayment() {
        XCTAssertEqual(engine.rule(from: "QP")?.maxStayMinutes, 15)
        XCTAssertEqual(engine.rule(from: "1P")?.maxStayMinutes, 60)
        XCTAssertEqual(engine.rule(from: "MP2P")?.payment, .paid)
        XCTAssertEqual(engine.rule(from: "FP3P")?.payment, .free)
        XCTAssertEqual(engine.rule(from: "FP15")?.maxStayMinutes, 15)
    }

    func testRejectsRestrictedAndAmbiguousCodes() {
        for code in ["LZ", "PERMIT ZONE", "DISABILITY", "NO PARKING", "CLEARWAY", "MP"] {
            XCTAssertNil(engine.rule(from: code), code)
        }
    }

    func testWeekdayRuleIsInactiveOnWeekend() {
        let record = RestrictionRecord(zoneNumber: 1, days: "Mon-Fri", start: "07:00:00", finish: "19:00:00", display: "MP2P")
        XCTAssertNotNil(engine.activeRule(in: [record], at: localDate("2026-08-14 09:00")))
        XCTAssertNil(engine.activeRule(in: [record], at: localDate("2026-08-15 09:00")))
    }

    func testCrossMidnightRuleUsesPreviousDayAfterMidnight() {
        let friday = RestrictionRecord(zoneNumber: 1, days: "Fri", start: "22:00:00", finish: "02:00:00", display: "1P")
        XCTAssertNotNil(engine.activeRule(in: [friday], at: localDate("2026-08-15 01:00")))
        XCTAssertNil(engine.activeRule(in: [friday], at: localDate("2026-08-15 03:00")))
    }

    func testActualCityDayRangesIncludeMonSatAndMonThu() {
        let monSat = RestrictionRecord(zoneNumber: 1, days: "Mon-Sat", start: "07:00:00", finish: "19:00:00", display: "2P")
        let monThu = RestrictionRecord(zoneNumber: 1, days: "Mon-Thu", start: "07:00:00", finish: "19:00:00", display: "2P")
        XCTAssertNotNil(engine.activeRule(in: [monSat], at: localDate("2026-08-15 09:00")))
        XCTAssertNil(engine.activeRule(in: [monThu], at: localDate("2026-08-14 09:00")))
    }

    func testRequestedStayIsHardEligibilityFilter() {
        let oneHour = engine.rule(from: "1P")!
        XCTAssertTrue(engine.isEligible(oneHour, for: .oneHour))
        XCTAssertFalse(engine.isEligible(oneHour, for: .twoHours))
    }

    func testLongStayPresetsDoNotTreatThreeHourParkingAsAllDay() {
        let threeHour = engine.rule(from: "3P")!

        XCTAssertTrue(engine.isEligible(threeHour, for: .threeHours))
        XCTAssertFalse(engine.isEligible(threeHour, for: .fourHours))
        XCTAssertFalse(engine.isEligible(threeHour, for: .eightHours))
    }

    private func localDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}

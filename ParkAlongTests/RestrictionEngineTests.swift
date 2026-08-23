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
        XCTAssertTrue(engine.isEligible(oneHour, controlledSeconds: 60 * 60))
        XCTAssertFalse(engine.isEligible(oneHour, controlledSeconds: 120 * 60))
    }

    func testLongStayPresetsDoNotTreatThreeHourParkingAsAllDay() {
        let threeHour = engine.rule(from: "3P")!

        XCTAssertTrue(engine.isEligible(threeHour, controlledSeconds: 180 * 60))
        XCTAssertFalse(engine.isEligible(threeHour, controlledSeconds: 240 * 60))
        XCTAssertFalse(engine.isEligible(threeHour, controlledSeconds: 480 * 60))
    }

    func testWeeklyScheduleBuildsSevenDayPaidFreeAndUnrestrictedTimeline() {
        let records = [
            RestrictionRecord(zoneNumber: 1, days: "Mon-Fri", start: "07:00:00", finish: "19:00:00", display: "MP2P"),
            RestrictionRecord(zoneNumber: 1, days: "Sat", start: "09:00:00", finish: "13:00:00", display: "FP3P"),
        ]
        let plan = ParkingPlan(arrival: localDate("2026-08-14 10:00"), durationMinutes: 60)

        let days = engine.weeklySchedule(records, plan: plan)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].blocks.map(\.kind), [.unrestricted, .restricted, .unrestricted])
        XCTAssertEqual(days[0].blocks[1].maxStayMinutes, 120)
        XCTAssertEqual(days[0].blocks[1].isPaid, true)
        XCTAssertEqual(days[1].blocks[1].maxStayMinutes, 180)
        XCTAssertEqual(days[1].blocks[1].isPaid, false)
        XCTAssertEqual(days[2].blocks.map(\.kind), [.unrestricted])
    }

    func testWeeklyScheduleMarksUnparseableActiveRuleUnknown() {
        let records = [
            RestrictionRecord(zoneNumber: 1, days: "Daily", start: "07:00:00", finish: "19:00:00", display: "EVENT ZONE"),
        ]
        let plan = ParkingPlan(arrival: localDate("2026-08-14 10:00"), durationMinutes: 60)

        let days = engine.weeklySchedule(records, plan: plan)

        XCTAssertEqual(days[0].blocks[1].kind, .unknown)
        XCTAssertEqual(days[0].blocks[1].title, "Check posted signs")
    }

    private func localDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}

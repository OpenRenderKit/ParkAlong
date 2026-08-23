import XCTest
@testable import ParkAlong

final class ParkingRuleResolverTests: XCTestCase {
    private let resolver = ParkingRuleResolver(timeZone: TimeZone(identifier: "Australia/Melbourne")!)

    func testWeekdayScheduleResolvesCurrentLimitWindowAndHourlyPrice() {
        let location = fixtureLocation(
            schedules: [
                .init(days: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 17 * 60 + 30,
                      maxStayMinutes: 120, restrictionText: "2P Meter", appliesOnPublicHolidays: false,
                      outsideWindowMeansUnrestricted: true)
            ],
            tariffs: [
                .init(effectiveFrom: localDate("2026-08-01 00:00"), effectiveTo: nil,
                      days: [2, 3, 4, 5, 6, 7], startMinutes: 9 * 60, endMinutes: 17 * 60 + 30,
                      hourlyCents: 360, freeMinutes: 60, dailyCapCents: 650, tiers: [])
            ]
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-20 10:15"), duration: .twoHours)

        XCTAssertEqual(resolved?.timeLimitText, "2P until 5:30 pm")
        XCTAssertEqual(resolved?.restrictionWindow, "Active now · ends 5:30 pm")
        XCTAssertEqual(resolved?.price.primaryText, "$3.60 for 2 hours")
        XCTAssertEqual(resolved?.price.detail, "First hour free · then $3.60/hr · $6.50 daily cap")
        XCTAssertEqual(resolved?.classification, .staticOnly)
    }

    func testOutsideOfficialWindowResolvesUnrestrictedAndFree() {
        let location = fixtureLocation(
            schedules: [
                .init(days: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 17 * 60,
                      maxStayMinutes: 120, restrictionText: "2P Meter", appliesOnPublicHolidays: false,
                      outsideWindowMeansUnrestricted: true)
            ],
            tariffs: []
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-20 19:00"), duration: .threeHours)

        XCTAssertEqual(resolved?.timeLimitText, "No timed limit right now")
        XCTAssertEqual(resolved?.price.primaryText, "Free right now")
    }

    func testOvernightScheduleUsesPreviousDayAfterMidnight() {
        let location = fixtureLocation(
            schedules: [
                .init(days: [6], startMinutes: 22 * 60, endMinutes: 2 * 60,
                      maxStayMinutes: 60, restrictionText: "1P", appliesOnPublicHolidays: true,
                      outsideWindowMeansUnrestricted: false)
            ],
            tariffs: []
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-22 01:00"), duration: .oneHour)

        XCTAssertEqual(resolved?.timeLimitText, "1P until 2:00 am")
    }

    func testPublicHolidayDoesNotApplyUnlessScheduleExplicitlyAllowsIt() {
        let location = fixtureLocation(
            schedules: [
                .init(days: [2, 3, 4, 5, 6], startMinutes: 9 * 60, endMinutes: 17 * 60,
                      maxStayMinutes: 120, restrictionText: "2P Meter", appliesOnPublicHolidays: false,
                      outsideWindowMeansUnrestricted: true)
            ],
            tariffs: []
        )

        let resolved = resolver.resolve(
            location: location,
            at: localDate("2026-01-26 10:00"),
            duration: .oneHour,
            isPublicHoliday: true
        )

        XCTAssertEqual(resolved?.timeLimitText, "No timed limit right now")
        XCTAssertEqual(resolved?.price.primaryText, "Free right now")
    }

    func testSteppedFacilityTariffUsesRequestedDuration() {
        let location = fixtureLocation(
            schedules: [
                .init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      maxStayMinutes: nil, restrictionText: "Open 24 hours", appliesOnPublicHolidays: true,
                      outsideWindowMeansUnrestricted: false)
            ],
            tariffs: [
                .init(effectiveFrom: localDate("2026-07-01 00:00"), effectiveTo: nil,
                      days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      hourlyCents: nil, freeMinutes: 0, dailyCapCents: 2800,
                      tiers: [.init(upToMinutes: 30, priceCents: 420), .init(upToMinutes: 60, priceCents: 630), .init(upToMinutes: 120, priceCents: 1050)])
            ]
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-23 12:00"), duration: .twoHours)

        XCTAssertEqual(resolved?.price.primaryText, "$10.50 for 2 hours")
        XCTAssertEqual(resolved?.price.detail, "Up to $28.00 daily")
    }

    func testExpiredTariffFailsClosedInsteadOfDisplayingOldPrice() {
        let location = fixtureLocation(
            schedules: [],
            tariffs: [
                .init(effectiveFrom: localDate("2024-07-01 00:00"), effectiveTo: localDate("2025-06-30 23:59"),
                      days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      hourlyCents: 200, freeMinutes: 0, dailyCapCents: nil, tiers: [])
            ]
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-23 12:00"), duration: .oneHour)

        XCTAssertEqual(resolved?.timeLimitText, "Check posted signs")
        XCTAssertEqual(resolved?.price.primaryText, "Price not verified")
        XCTAssertEqual(resolved?.price.detail, "Check the meter or facility notice")
    }

    func testOutsideCurrentVerifiedPaymentWindowShowsFreeRightNow() {
        let location = fixtureLocation(
            schedules: [
                .init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      maxStayMinutes: nil, restrictionText: "No maximum stay", appliesOnPublicHolidays: true,
                      outsideWindowMeansUnrestricted: false)
            ],
            tariffs: [
                .init(effectiveFrom: localDate("2026-08-01 00:00"), effectiveTo: nil,
                      days: [2, 3, 4, 5, 6, 7], startMinutes: 9 * 60, endMinutes: 17 * 60 + 30,
                      hourlyCents: 360, freeMinutes: 60, dailyCapCents: nil, tiers: [])
            ]
        )

        let resolved = resolver.resolve(location: location, at: localDate("2026-08-23 12:00"), duration: .twoHours)

        XCTAssertEqual(resolved?.price.primaryText, "Free right now")
        XCTAssertEqual(resolved?.price.detail, "Outside verified payment hours")
    }

    func testFreePeriodWithoutHourlyRateDoesNotChargeDailyCapEarly() {
        let location = fixtureLocation(
            schedules: [
                .init(days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      maxStayMinutes: nil, restrictionText: "Open 24 hours", appliesOnPublicHolidays: true,
                      outsideWindowMeansUnrestricted: false)
            ],
            tariffs: [
                .init(effectiveFrom: localDate("2026-01-01 00:00"), effectiveTo: nil,
                      days: Array(1...7), startMinutes: 0, endMinutes: 24 * 60,
                      hourlyCents: nil, freeMinutes: 180, dailyCapCents: 500, tiers: [])
            ]
        )

        let oneHour = resolver.resolve(location: location, at: localDate("2026-08-23 12:00"), duration: .oneHour)

        XCTAssertEqual(oneHour?.price.primaryText, "Free for 1 hour")
    }

    private func fixtureLocation(schedules: [ParkingSchedule], tariffs: [ParkingTariff]) -> StaticParkingLocation {
        .init(
            id: "fixture", name: "Fixture car park", municipality: "Test Council",
            coordinate: .melbourneCBD, kind: .offStreet, archetype: .cbdRetail,
            capacity: 100, accessibleSpaces: 4, schedules: schedules, tariffs: tariffs,
            source: .init(id: "fixture", name: "Test Council", sourceURL: URL(string: "https://example.com")!,
                          licenseName: "Official public page", licenseURL: nil,
                          datasetUpdatedAt: nil, checkedAt: localDate("2026-08-23 00:00")),
            classification: .staticOnly, predictionEvidence: nil
        )
    }

    private func localDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}

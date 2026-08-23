import XCTest
@testable import ParkAlong

final class PredictionRankingCacheTests: XCTestCase {
    func testSegmentKeyMatchesGeneratorNormalization() {
        let metadata = ZoneMetadata(zoneNumber: 1, streetName: "Collins Street", fromStreet: "Swanston Street", toStreet: "Russell St.", coordinate: .melbourneCBD, sensorCount: 4)
        XCTAssertEqual(metadata.segmentKey, "collinsst|russellst|swanstonst")
    }

    func testShortArrivalWeightsLiveAtEightyPercent() {
        let prediction = PredictionEngine.estimate(liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.8, etaMinutes: 15, sampleCount: 500)
        XCTAssertEqual(prediction.expectedAvailable, 3.6, accuracy: 0.001)
        XCTAssertEqual(prediction.liveWeight, 0.8, accuracy: 0.001)
    }

    func testLongerArrivalReducesLiveWeightAndClampsRange() {
        let prediction = PredictionEngine.estimate(liveAvailable: 20, trustedBayCount: 5, historicalOccupiedRatio: -1, etaMinutes: 180, sampleCount: 2)
        XCTAssertLessThan(prediction.liveWeight, 0.8)
        XCTAssertGreaterThanOrEqual(prediction.lowerBound, 0)
        XCTAssertLessThanOrEqual(prediction.upperBound, 5)
    }

    func testRankingMakesAvailabilityDominateProximity() {
        let candidates = [
            RankingCandidate(zoneNumber: 1, predictedAvailable: 5, walkingMetres: 850, confidence: 0.8),
            RankingCandidate(zoneNumber: 2, predictedAvailable: 1, walkingMetres: 50, confidence: 1)
        ]
        XCTAssertEqual(RankingEngine.rank(candidates).first?.zoneNumber, 1)
    }

    func testCacheExpiresAtTTLBoundary() {
        let stored = Date(timeIntervalSince1970: 100)
        let cached = TimedValue(value: "zones", storedAt: stored)
        XCTAssertEqual(cached.value(ifFreshAt: stored.addingTimeInterval(119), ttl: 120), "zones")
        XCTAssertNil(cached.value(ifFreshAt: stored.addingTimeInterval(120), ttl: 120))
    }

    func testStaticPredictionRequiresCapacitySamplesAndCalibration() {
        let context = ParkingDemandContext(weekday: 3, minuteOfDay: 10 * 60, isPublicHoliday: false,
                                           isSchoolHoliday: false, clearWeatherIndex: 0.5,
                                           eventIntensity: 0, trafficIndex: 1, hourlyPriceCents: 300,
                                           maxStayMinutes: 120)
        XCTAssertNil(PredictionEngine.staticEstimate(
            capacity: nil,
            evidence: .init(sampleCount: 1_000, calibrationError: 0.05, baselineOccupiedRatio: 0.7, sourceDescription: "survey", observedThrough: nil),
            archetype: .cbdRetail, context: context
        ))
        XCTAssertNil(PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: .init(sampleCount: 99, calibrationError: 0.05, baselineOccupiedRatio: 0.7, sourceDescription: "survey", observedThrough: nil),
            archetype: .cbdRetail, context: context
        ))
        XCTAssertNil(PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: .init(sampleCount: 1_000, calibrationError: 0.11, baselineOccupiedRatio: 0.7, sourceDescription: "survey", observedThrough: nil),
            archetype: .cbdRetail, context: context
        ))
    }

    func testValidatedStaticPredictionProducesBoundedEstimate() {
        let prediction = PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: .init(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.7, sourceDescription: "held-out survey", observedThrough: nil),
            archetype: .cbdRetail,
            context: .init(weekday: 3, minuteOfDay: 11 * 60, isPublicHoliday: false,
                           isSchoolHoliday: false, clearWeatherIndex: 0.5, eventIntensity: 0,
                           trafficIndex: 1, hourlyPriceCents: 300, maxStayMinutes: 120)
        )

        XCTAssertNotNil(prediction)
        XCTAssertGreaterThan(prediction!.expectedAvailable, 0)
        XCTAssertLessThan(prediction!.expectedAvailable, 100)
        XCTAssertGreaterThanOrEqual(prediction!.lowerBound, 0)
        XCTAssertLessThanOrEqual(prediction!.upperBound, 100)
        XCTAssertGreaterThan(prediction!.confidence, 0.5)
    }

    func testBeachDemandRisesWithClearSchoolHolidayWeekendWeather() {
        let evidence = PredictionEvidence(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.55, sourceDescription: "survey", observedThrough: nil)
        let quiet = PredictionEngine.staticEstimate(
            capacity: 100, evidence: evidence, archetype: .beachTourism,
            context: .init(weekday: 3, minuteOfDay: 11 * 60, isPublicHoliday: false,
                           isSchoolHoliday: false, clearWeatherIndex: 0.1, eventIntensity: 0,
                           trafficIndex: 0.8, hourlyPriceCents: 400, maxStayMinutes: 240)
        )!
        let busy = PredictionEngine.staticEstimate(
            capacity: 100, evidence: evidence, archetype: .beachTourism,
            context: .init(weekday: 7, minuteOfDay: 13 * 60, isPublicHoliday: false,
                           isSchoolHoliday: true, clearWeatherIndex: 1, eventIntensity: 0.4,
                           trafficIndex: 1.3, hourlyPriceCents: 0, maxStayMinutes: 240)
        )!

        XCTAssertLessThan(busy.expectedAvailable, quiet.expectedAvailable)
    }

    func testHigherPriceAndShorterLimitIncreaseExpectedTurnover() {
        let evidence = PredictionEvidence(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.75, sourceDescription: "survey", observedThrough: nil)
        let common = (weekday: 5, minute: 14 * 60)
        let freeLong = PredictionEngine.staticEstimate(
            capacity: 80, evidence: evidence, archetype: .cbdRetail,
            context: .init(weekday: common.weekday, minuteOfDay: common.minute, isPublicHoliday: false,
                           isSchoolHoliday: false, clearWeatherIndex: 0.5, eventIntensity: 0,
                           trafficIndex: 1, hourlyPriceCents: 0, maxStayMinutes: 240)
        )!
        let pricedShort = PredictionEngine.staticEstimate(
            capacity: 80, evidence: evidence, archetype: .cbdRetail,
            context: .init(weekday: common.weekday, minuteOfDay: common.minute, isPublicHoliday: false,
                           isSchoolHoliday: false, clearWeatherIndex: 0.5, eventIntensity: 0,
                           trafficIndex: 1, hourlyPriceCents: 500, maxStayMinutes: 60)
        )!

        XCTAssertGreaterThan(pricedShort.expectedAvailable, freeLong.expectedAvailable)
    }
}

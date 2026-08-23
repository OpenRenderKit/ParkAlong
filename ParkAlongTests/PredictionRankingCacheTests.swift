import XCTest
@testable import ParkAlong

final class PredictionRankingCacheTests: XCTestCase {
    func testSegmentKeyMatchesGeneratorNormalization() {
        let metadata = ZoneMetadata(zoneNumber: 1, streetName: "Collins Street", fromStreet: "Swanston Street", toStreet: "Russell St.", coordinate: .melbourneCBD, sensorCount: 4)
        XCTAssertEqual(metadata.segmentKey, "collinsst|russellst|swanstonst")
    }

    func testImmediateLiveReadingIsPresentedAsObservationNotFakeConfidence() {
        let prediction = PredictionEngine.estimate(
            liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.8,
            etaMinutes: 0, validation: nil, forecastDate: Date()
        )
        XCTAssertEqual(prediction.expectedAvailable, 4)
        XCTAssertEqual(prediction.probabilityAtLeastOne, 1)
        XCTAssertEqual(prediction.evidenceTier, .liveObserved)
        XCTAssertNil(prediction.validation)
    }

    func testFutureForecastWithoutMeasuredValidationAbstains() {
        let prediction = PredictionEngine.estimate(
            liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.8,
            etaMinutes: 60, validation: nil, forecastDate: Date()
        )
        XCTAssertNil(prediction.expectedAvailable)
        XCTAssertNil(prediction.probabilityAtLeastOne)
        XCTAssertEqual(prediction.abstentionReason, .missingValidation)
    }

    func testValidatedLiveInformedForecastProducesCalibratedRangeAndProbability() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
            intervalCoverage: 0.89, observedThrough: date.addingTimeInterval(-86_400),
            modelVersion: "seasonal-v2"
        )
        let prediction = PredictionEngine.estimate(
            liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.8,
            etaMinutes: 60, validation: validation, forecastDate: date
        )
        XCTAssertEqual(prediction.evidenceTier, .liveInformed)
        XCTAssertNotNil(prediction.expectedAvailable)
        XCTAssertGreaterThanOrEqual(prediction.lowerBound!, 0)
        XCTAssertLessThanOrEqual(prediction.upperBound!, 10)
        XCTAssertTrue((0...1).contains(prediction.probabilityAtLeastOne!))
        XCTAssertEqual(prediction.modelVersion, "seasonal-v2")
    }

    func testForecastRangeUsesHeldOutIntervalRadiusRatherThanMeanError() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.01, brierScore: 0.12,
            intervalCoverage: 0.9, intervalRadius: 0.25,
            observedThrough: date.addingTimeInterval(-86_400), modelVersion: "conformal-v3"
        )

        let prediction = PredictionEngine.estimate(
            liveAvailable: 0, trustedBayCount: 20, historicalOccupiedRatio: 0.5,
            etaMinutes: 6 * 60, validation: validation, forecastDate: date
        )

        XCTAssertEqual(prediction.expectedAvailable, 10)
        XCTAssertEqual(prediction.lowerBound, 5)
        XCTAssertEqual(prediction.upperBound, 15)
    }

    func testAtLeastOneProbabilityUsesCapacityAwareBayProbability() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.05, brierScore: 0.12,
            intervalCoverage: 0.9, intervalRadius: 0.1,
            observedThrough: date.addingTimeInterval(-86_400), modelVersion: "probability-v3"
        )

        let prediction = PredictionEngine.historicalEstimate(
            capacity: 1, occupiedRatio: 0.5, horizonMinutes: 60,
            validation: validation, forecastDate: date
        )

        XCTAssertEqual(prediction.expectedAvailable, 0.5)
        XCTAssertEqual(prediction.probabilityAtLeastOne!, 0.5, accuracy: 0.000_001)
    }

    func testUnusableWidePredictionIntervalAbstains() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.01, brierScore: 0.12,
            intervalCoverage: 0.99, intervalRadius: 0.5,
            observedThrough: date.addingTimeInterval(-86_400), modelVersion: "wide-v3"
        )

        let prediction = PredictionEngine.estimate(
            liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.5,
            etaMinutes: 60, validation: validation, forecastDate: date
        )

        XCTAssertEqual(prediction.abstentionReason, .poorCalibration)
    }

    func testLongHorizonForecastDoesNotCarryTodaysLiveCountIntoTomorrow() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 2_000, normalizedMAE: 0.08, brierScore: 0.12,
            intervalCoverage: 0.89, observedThrough: date.addingTimeInterval(-86_400),
            modelVersion: "seasonal-v2"
        )

        let emptyNow = PredictionEngine.estimate(
            liveAvailable: 0, trustedBayCount: 10, historicalOccupiedRatio: 0.6,
            etaMinutes: 24 * 60, validation: validation, forecastDate: date
        )
        let fullNow = PredictionEngine.estimate(
            liveAvailable: 10, trustedBayCount: 10, historicalOccupiedRatio: 0.6,
            etaMinutes: 24 * 60, validation: validation, forecastDate: date
        )

        XCTAssertEqual(emptyNow.expectedAvailable, fullNow.expectedAvailable)
        XCTAssertEqual(emptyNow.liveWeight, 0)
        XCTAssertEqual(emptyNow.evidenceTier, .historical)
    }

    func testStaleModelAbstainsEvenWithLargeSampleCount() {
        let date = Date()
        let validation = ForecastValidation(
            sampleCount: 20_000, normalizedMAE: 0.05, brierScore: 0.10,
            intervalCoverage: 0.9, observedThrough: date.addingTimeInterval(-3 * 365 * 86_400),
            modelVersion: "stale-v1"
        )
        let prediction = PredictionEngine.estimate(
            liveAvailable: 4, trustedBayCount: 10, historicalOccupiedRatio: 0.8,
            etaMinutes: 60, validation: validation, forecastDate: date
        )
        XCTAssertEqual(prediction.abstentionReason, .staleModel)
    }

    func testRankingMakesAvailabilityDominateProximity() {
        let candidates = [
            RankingCandidate(zoneNumber: 1, predictedAvailable: 5, walkingMetres: 850, probabilityAtLeastOne: 0.95),
            RankingCandidate(zoneNumber: 2, predictedAvailable: 1, walkingMetres: 50, probabilityAtLeastOne: 0.55)
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
            evidence: evidence(sampleCount: 1_000, calibrationError: 0.05),
            archetype: .cbdRetail, context: context
        ))
        XCTAssertNil(PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: evidence(sampleCount: 99, calibrationError: 0.05),
            archetype: .cbdRetail, context: context
        ))
        XCTAssertNil(PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: evidence(sampleCount: 1_000, calibrationError: 0.11),
            archetype: .cbdRetail, context: context
        ))
    }

    func testValidatedStaticPredictionProducesBoundedEstimate() {
        let prediction = PredictionEngine.staticEstimate(
            capacity: 100,
            evidence: evidence(sampleCount: 2_000, calibrationError: 0.06),
            archetype: .cbdRetail,
            context: .init(weekday: 3, minuteOfDay: 11 * 60, isPublicHoliday: false,
                           isSchoolHoliday: false, clearWeatherIndex: 0.5, eventIntensity: 0,
                           trafficIndex: 1, hourlyPriceCents: 300, maxStayMinutes: 120)
        )

        XCTAssertNotNil(prediction)
        XCTAssertGreaterThan(prediction!.expectedAvailable!, 0)
        XCTAssertLessThan(prediction!.expectedAvailable!, 100)
        XCTAssertGreaterThanOrEqual(prediction!.lowerBound!, 0)
        XCTAssertLessThanOrEqual(prediction!.upperBound!, 100)
        XCTAssertNotNil(prediction!.probabilityAtLeastOne)
    }

    func testBeachDemandRisesWithClearSchoolHolidayWeekendWeather() {
        let evidence = evidence(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.55)
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

        XCTAssertLessThan(busy.expectedAvailable!, quiet.expectedAvailable!)
    }

    func testHigherPriceAndShorterLimitIncreaseExpectedTurnover() {
        let evidence = evidence(sampleCount: 2_000, calibrationError: 0.06, baselineOccupiedRatio: 0.75)
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

        XCTAssertGreaterThan(pricedShort.expectedAvailable!, freeLong.expectedAvailable!)
    }

    private func evidence(
        sampleCount: Int,
        calibrationError: Double,
        baselineOccupiedRatio: Double = 0.7
    ) -> PredictionEvidence {
        .init(
            sampleCount: sampleCount, calibrationError: calibrationError,
            baselineOccupiedRatio: baselineOccupiedRatio, sourceDescription: "held-out survey",
            observedThrough: Date(), brierScore: 0.12, intervalCoverage: 0.9,
            modelVersion: "survey-v2"
        )
    }
}

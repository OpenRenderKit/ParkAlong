import XCTest
@testable import ParkingAvailability

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
}

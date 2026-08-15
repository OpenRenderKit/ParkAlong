import Foundation

enum PredictionEngine {
    static func estimate(
        liveAvailable: Int,
        trustedBayCount: Int,
        historicalOccupiedRatio: Double?,
        etaMinutes: Int,
        sampleCount: Int
    ) -> AvailabilityPrediction {
        let capacity = max(0, trustedBayCount)
        let live = Double(min(max(0, liveAvailable), capacity))
        let ratio = min(1, max(0, historicalOccupiedRatio ?? (capacity == 0 ? 1 : 1 - live / Double(capacity))))
        let historicalAvailable = Double(capacity) * (1 - ratio)
        let liveWeight = max(0.35, min(0.8, 0.8 - Double(max(0, etaMinutes - 15)) / 360))
        let expected = min(Double(capacity), max(0, liveWeight * live + (1 - liveWeight) * historicalAvailable))
        let confidence = min(1, max(0.2, sqrt(Double(max(0, sampleCount)) / 500)))
        let margin = 0.75 + (1 - confidence) * 2
        return AvailabilityPrediction(
            expectedAvailable: expected,
            lowerBound: max(0, Int(floor(expected - margin))),
            upperBound: min(capacity, Int(ceil(expected + margin))),
            liveWeight: liveWeight,
            confidence: confidence
        )
    }
}


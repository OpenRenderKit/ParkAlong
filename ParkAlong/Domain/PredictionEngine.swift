import Foundation

struct ParkingDemandContext: Equatable, Sendable {
    let weekday: Int
    let minuteOfDay: Int
    let isPublicHoliday: Bool
    let isSchoolHoliday: Bool
    /// Zero is poor outdoor weather; one is clear, attractive weather.
    let clearWeatherIndex: Double
    /// Zero means no known event; one means a major nearby event.
    let eventIntensity: Double
    /// One is ordinary traffic for this place and time.
    let trafficIndex: Double
    let hourlyPriceCents: Int?
    let maxStayMinutes: Int?
}

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

    static func staticEstimate(
        capacity: Int?,
        evidence: PredictionEvidence,
        archetype: ParkingArchetype,
        context: ParkingDemandContext
    ) -> AvailabilityPrediction? {
        guard let capacity, capacity > 0,
              evidence.sampleCount >= 100,
              evidence.calibrationError >= 0,
              evidence.calibrationError <= 0.10,
              (0...1).contains(evidence.baselineOccupiedRatio) else { return nil }

        let weekday = (2...6).contains(context.weekday)
        let weekend = context.weekday == 1 || context.weekday == 7
        let hour = Double(context.minuteOfDay) / 60
        var occupied = evidence.baselineOccupiedRatio

        switch archetype {
        case .cbdRetail:
            if weekday && (9..<18).contains(hour) { occupied += 0.06 }
            if weekend && (11..<17).contains(hour) { occupied += 0.04 }
        case .stationCommuter:
            if weekday && (7..<10).contains(hour) { occupied += 0.18 }
            if weekday && (16..<19).contains(hour) { occupied += 0.08 }
            if weekend { occupied -= 0.12 }
        case .hospitalUniversity:
            if weekday && (8..<17).contains(hour) { occupied += 0.10 }
            if context.isSchoolHoliday { occupied -= 0.04 }
        case .beachTourism:
            if weekend { occupied += 0.10 }
            if context.isSchoolHoliday { occupied += 0.08 }
            if (10..<17).contains(hour) { occupied += 0.06 }
            occupied += min(1, max(0, context.clearWeatherIndex)) * 0.10
        case .events:
            occupied += min(1, max(0, context.eventIntensity)) * 0.28
        case .residential:
            if hour < 8 || hour >= 18 { occupied += 0.08 }
        case .general:
            break
        }

        occupied += min(1, max(0, context.eventIntensity)) * 0.20
        occupied += min(1, max(-0.5, context.trafficIndex - 1)) * 0.08

        if context.hourlyPriceCents == 0 {
            occupied += 0.05
        } else if let price = context.hourlyPriceCents, price >= 400 {
            occupied -= 0.05
        }
        if let maxStay = context.maxStayMinutes, maxStay <= 60 { occupied -= 0.04 }

        if context.isPublicHoliday {
            switch archetype {
            case .beachTourism: occupied += 0.06
            case .stationCommuter, .hospitalUniversity: occupied -= 0.08
            default: occupied += 0.02
            }
        }

        occupied = min(0.98, max(0.05, occupied))
        let expected = Double(capacity) * (1 - occupied)
        let sampleStrength = min(1, log10(Double(evidence.sampleCount) / 100 + 1) / log10(51))
        let confidence = min(0.92, max(0.2, 0.48 + sampleStrength * 0.35 - evidence.calibrationError))
        let margin = max(1, Int(ceil(Double(capacity) * (evidence.calibrationError + (1 - confidence) * 0.08))))
        return AvailabilityPrediction(
            expectedAvailable: expected,
            lowerBound: max(0, Int(floor(expected)) - margin),
            upperBound: min(capacity, Int(ceil(expected)) + margin),
            liveWeight: 0,
            confidence: confidence
        )
    }
}

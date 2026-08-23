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
        validation: ForecastValidation?,
        forecastDate: Date
    ) -> AvailabilityPrediction {
        let capacity = max(0, trustedBayCount)
        let live = Double(min(max(0, liveAvailable), capacity))
        guard capacity > 0 else { return abstained(.missingCapacity, horizonMinutes: etaMinutes) }
        if etaMinutes <= 5 {
            return AvailabilityPrediction(
                expectedAvailable: live, lowerBound: Int(live), upperBound: Int(live),
                probabilityAtLeastOne: live > 0 ? 1 : 0, liveWeight: 1,
                evidenceTier: .liveObserved, horizonMinutes: max(0, etaMinutes), modelVersion: nil,
                validation: nil, abstentionReason: nil
            )
        }
        guard let historicalOccupiedRatio else { return abstained(.missingHistory, horizonMinutes: etaMinutes) }
        guard let validation else { return abstained(.missingValidation, horizonMinutes: etaMinutes) }
        if let reason = validationFailure(validation, forecastDate: forecastDate) {
            return abstained(reason, horizonMinutes: etaMinutes, validation: validation)
        }
        let ratio = min(1, max(0, historicalOccupiedRatio))
        let historicalAvailable = Double(capacity) * (1 - ratio)
        let liveDecay = 1 - Double(max(0, etaMinutes - 15)) / Double(6 * 60 - 15)
        let liveWeight = max(0, min(0.8, 0.8 * liveDecay))
        let expected = min(Double(capacity), max(0, liveWeight * live + (1 - liveWeight) * historicalAvailable))
        let margin = max(1, Int(ceil(Double(capacity) * validation.intervalRadius)))
        return AvailabilityPrediction(
            expectedAvailable: expected,
            lowerBound: max(0, Int(floor(expected)) - margin),
            upperBound: min(capacity, Int(ceil(expected)) + margin),
            probabilityAtLeastOne: probabilityAtLeastOne(expected: expected, capacity: capacity),
            liveWeight: liveWeight,
            evidenceTier: liveWeight > 0 ? .liveInformed : .historical,
            horizonMinutes: max(0, etaMinutes),
            modelVersion: validation.modelVersion,
            validation: validation,
            abstentionReason: nil
        )
    }

    static func historicalEstimate(
        capacity: Int,
        occupiedRatio: Double,
        horizonMinutes: Int,
        validation: ForecastValidation?,
        forecastDate: Date
    ) -> AvailabilityPrediction {
        guard capacity > 0 else { return abstained(.missingCapacity, horizonMinutes: horizonMinutes) }
        guard let validation else { return abstained(.missingValidation, horizonMinutes: horizonMinutes) }
        if let reason = validationFailure(validation, forecastDate: forecastDate) {
            return abstained(reason, horizonMinutes: horizonMinutes, validation: validation)
        }
        let expected = Double(capacity) * (1 - min(1, max(0, occupiedRatio)))
        let margin = max(1, Int(ceil(Double(capacity) * validation.intervalRadius)))
        return AvailabilityPrediction(
            expectedAvailable: expected, lowerBound: max(0, Int(floor(expected)) - margin),
            upperBound: min(capacity, Int(ceil(expected)) + margin),
            probabilityAtLeastOne: probabilityAtLeastOne(expected: expected, capacity: capacity), liveWeight: 0,
            evidenceTier: .historical, horizonMinutes: max(0, horizonMinutes),
            modelVersion: validation.modelVersion, validation: validation, abstentionReason: nil
        )
    }

    static func staticEstimate(
        capacity: Int?,
        evidence: PredictionEvidence,
        archetype: ParkingArchetype,
        context: ParkingDemandContext,
        forecastDate: Date = .now
    ) -> AvailabilityPrediction? {
        guard let capacity, capacity > 0,
              evidence.sampleCount >= 500,
              evidence.calibrationError >= 0,
              evidence.calibrationError <= 0.10,
              (0...1).contains(evidence.baselineOccupiedRatio),
              let brierScore = evidence.brierScore,
              let intervalCoverage = evidence.intervalCoverage,
              let observedThrough = evidence.observedThrough,
              let modelVersion = evidence.modelVersion else { return nil }
        let validation = ForecastValidation(
            sampleCount: evidence.sampleCount, normalizedMAE: evidence.calibrationError,
            brierScore: brierScore, intervalCoverage: intervalCoverage,
            observedThrough: observedThrough, modelVersion: modelVersion
        )
        guard validationFailure(validation, forecastDate: forecastDate) == nil else { return nil }

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
        let margin = max(1, Int(ceil(Double(capacity) * evidence.calibrationError)))
        return AvailabilityPrediction(
            expectedAvailable: expected,
            lowerBound: max(0, Int(floor(expected)) - margin),
            upperBound: min(capacity, Int(ceil(expected)) + margin),
            probabilityAtLeastOne: probabilityAtLeastOne(expected: expected, capacity: capacity),
            liveWeight: 0,
            evidenceTier: .historical,
            horizonMinutes: 0,
            modelVersion: modelVersion,
            validation: validation,
            abstentionReason: nil
        )
    }

    private static func validationFailure(
        _ validation: ForecastValidation,
        forecastDate: Date
    ) -> ForecastAbstentionReason? {
        guard validation.sampleCount >= 500 else { return .insufficientSupport }
        guard (0...0.20).contains(validation.normalizedMAE),
              (0...0.20).contains(validation.brierScore),
              (0.80...1).contains(validation.intervalCoverage),
              (0...0.35).contains(validation.intervalRadius) else { return .poorCalibration }
        let age = forecastDate.timeIntervalSince(validation.observedThrough)
        guard age >= -86_400, age <= 2 * 365 * 86_400 else { return .staleModel }
        return nil
    }

    private static func probabilityAtLeastOne(expected: Double, capacity: Int) -> Double {
        guard capacity > 0 else { return 0 }
        let perBayAvailable = min(1, max(0, expected / Double(capacity)))
        return min(1, max(0, 1 - pow(1 - perBayAvailable, Double(capacity))))
    }

    private static func abstained(
        _ reason: ForecastAbstentionReason,
        horizonMinutes: Int,
        validation: ForecastValidation? = nil
    ) -> AvailabilityPrediction {
        AvailabilityPrediction(
            expectedAvailable: nil, lowerBound: nil, upperBound: nil,
            probabilityAtLeastOne: nil, liveWeight: 0, evidenceTier: .abstained,
            horizonMinutes: max(0, horizonMinutes), modelVersion: validation?.modelVersion,
            validation: validation, abstentionReason: reason
        )
    }
}

import Foundation

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    static let melbourneCBD = Coordinate(latitude: -37.8136, longitude: 144.9631)
}

struct ParkingViewport: Codable, Hashable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let zoomLevel: Double

    init(south: Double, west: Double, north: Double, east: Double, zoomLevel: Double) {
        precondition(south < north && west < east, "Viewport bounds must have positive area")
        self.south = max(-90, south)
        self.west = max(-180, west)
        self.north = min(90, north)
        self.east = min(180, east)
        self.zoomLevel = max(0, zoomLevel)
    }

    var center: Coordinate {
        .init(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }

    var latitudeSpan: Double { north - south }
    var longitudeSpan: Double { east - west }

    func contains(_ coordinate: Coordinate) -> Bool {
        (south...north).contains(coordinate.latitude) && (west...east).contains(coordinate.longitude)
    }

    func padded(by fraction: Double) -> ParkingViewport {
        let amount = max(0, fraction)
        return ParkingViewport(
            south: south - latitudeSpan * amount,
            west: west - longitudeSpan * amount,
            north: north + latitudeSpan * amount,
            east: east + longitudeSpan * amount,
            zoomLevel: zoomLevel
        )
    }

    func materiallyDiffers(from other: ParkingViewport) -> Bool {
        let latitudeThreshold = max(latitudeSpan, other.latitudeSpan) * 0.15
        let longitudeThreshold = max(longitudeSpan, other.longitudeSpan) * 0.15
        return abs(center.latitude - other.center.latitude) > latitudeThreshold
            || abs(center.longitude - other.center.longitude) > longitudeThreshold
            || abs(latitudeSpan - other.latitudeSpan) > latitudeThreshold
            || abs(longitudeSpan - other.longitudeSpan) > longitudeThreshold
            || Int(zoomLevel.rounded(.down)) != Int(other.zoomLevel.rounded(.down))
    }

    var queryRadiusMetres: Int {
        let northEast = Coordinate(latitude: north, longitude: east)
        return max(250, Int(ceil(Self.distance(from: center, to: northEast) * 1.2)))
    }

    private static func distance(from lhs: Coordinate, to rhs: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let value = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(value), sqrt(1 - value))
    }
}

enum StayDuration: Int, CaseIterable, Codable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case oneHour = 60
    case twoHours = 120
    case threeHours = 180
    case fourHours = 240
    case sixHours = 360
    case eightHours = 480

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .fifteenMinutes: "15m"
        case .oneHour: "1h"
        case .twoHours: "2h"
        case .threeHours: "3h"
        case .fourHours: "4h"
        case .sixHours: "6h"
        case .eightHours: "8h"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .threeHours: "3 hours"
        case .fourHours: "4 hours"
        case .sixHours: "6 hours"
        case .eightHours: "8 hours"
        }
    }

    var selectionDescription: String {
        ParkingPlan.durationDescription(minutes: rawValue)
    }
}

struct ParkingPlan: Codable, Hashable, Sendable {
    let arrival: Date
    let durationMinutes: Int
    let isPublicHoliday: Bool

    init(arrival: Date, durationMinutes: Int, isPublicHoliday: Bool = false) {
        precondition((1...(7 * 24 * 60)).contains(durationMinutes), "Parking duration must be between one minute and seven days")
        self.arrival = arrival
        self.durationMinutes = durationMinutes
        self.isPublicHoliday = isPublicHoliday
    }

    init(arrival: Date, duration: StayDuration, isPublicHoliday: Bool = false) {
        self.init(arrival: arrival, durationMinutes: duration.rawValue, isPublicHoliday: isPublicHoliday)
    }

    var departure: Date { arrival.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var selectionDescription: String { Self.durationDescription(minutes: durationMinutes) }
    var durationLabel: String { Self.durationLabel(minutes: durationMinutes) }

    static func durationDescription(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)-minute" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour" }
        return durationLabel(minutes: minutes)
    }

    static func durationLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) hour\(hours == 1 ? "" : "s")" }
        return "\(hours) hr \(remainder) min"
    }
}

enum ParkingScheduleBlockKind: String, Codable, Sendable {
    case restricted
    case unrestricted
    case unknown
}

struct ParkingScheduleBlock: Identifiable, Equatable, Sendable {
    let id: String
    let startMinutes: Int
    let endMinutes: Int
    let kind: ParkingScheduleBlockKind
    let title: String
    let detail: String?
    let maxStayMinutes: Int?
    let isPaid: Bool?
}

struct ParkingScheduleDay: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let weekday: Int
    let blocks: [ParkingScheduleBlock]
}

enum SensorStatus: String, Codable, Sendable {
    case present = "Present"
    case unoccupied = "Unoccupied"
    case unknown

    init(apiValue: String) {
        self = SensorStatus(rawValue: apiValue) ?? .unknown
    }
}

struct SensorReading: Hashable, Sendable {
    let kerbsideID: Int
    let zoneNumber: Int?
    let status: SensorStatus
    let timestamp: Date
    let coordinate: Coordinate
}

struct SensorAggregateRow: Hashable, Sendable {
    let zoneNumber: Int
    let status: SensorStatus
    let bayCount: Int
    let newestTimestamp: Date
}

struct AvailabilityStats: Equatable, Sendable {
    let available: Int
    let total: Int
    let newestTimestamp: Date
}

struct ZoneMetadata: Codable, Hashable, Sendable {
    let zoneNumber: Int
    let streetName: String
    let fromStreet: String?
    let toStreet: String?
    let coordinate: Coordinate
    let sensorCount: Int

    var segmentLabel: String {
        let crossStreets: [String] = [fromStreet, toStreet].compactMap { $0 }.filter { !$0.isEmpty }
        return crossStreets.isEmpty ? streetName : "\(streetName) · \(crossStreets.joined(separator: " to "))"
    }

    var segmentKey: String {
        let street = Self.canonicalStreet(streetName)
        let crossStreets = [Self.canonicalStreet(fromStreet ?? ""), Self.canonicalStreet(toStreet ?? "")].sorted()
        return ([street] + crossStreets).joined(separator: "|")
    }

    private static func canonicalStreet(_ value: String) -> String {
        var tokens = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let suffixes = [
            "street": "st", "road": "rd", "avenue": "ave", "lane": "ln", "place": "pl",
            "parade": "pde", "boulevard": "blvd", "drive": "dr", "terrace": "tce"
        ]
        if let last = tokens.last, let replacement = suffixes[last] { tokens[tokens.count - 1] = replacement }
        return tokens.joined()
    }
}

struct RestrictionRecord: Codable, Hashable, Sendable {
    let zoneNumber: Int
    let days: String
    let start: String
    let finish: String
    let display: String

    enum CodingKeys: String, CodingKey {
        case zoneNumber = "parkingzone"
        case days = "restriction_days"
        case start = "time_restrictions_start"
        case finish = "time_restrictions_finish"
        case display = "restriction_display"
    }
}

enum ParkingPaymentStatus: String, Codable, Sendable {
    case paid = "Paid"
    case free = "Free"
    case unknown = "Payment varies"
}

struct ParkingRule: Equatable, Sendable {
    let code: String
    let maxStayMinutes: Int
    let payment: ParkingPaymentStatus

    var plainEnglish: String {
        let duration: String
        if maxStayMinutes < 60 {
            duration = "Up to \(maxStayMinutes) minutes"
        } else {
            let hours = maxStayMinutes / 60
            duration = "Up to \(hours) hour\(hours == 1 ? "" : "s")"
        }
        switch payment {
        case .paid: return "\(duration), meter required"
        case .free: return "\(duration), free"
        case .unknown: return duration
        }
    }
}

struct HistoricalBucket: Codable, Hashable, Sendable {
    let segmentKey: String
    let weekday: Int
    let interval: Int
    let occupiedRatio: Double
    let turnover: Double
    let sampleCount: Int
    let observationState: HistoricalObservationState?
    let observedThrough: Date?

    init(
        segmentKey: String,
        weekday: Int,
        interval: Int,
        occupiedRatio: Double,
        turnover: Double,
        sampleCount: Int,
        observationState: HistoricalObservationState? = nil,
        observedThrough: Date? = nil
    ) {
        self.segmentKey = segmentKey
        self.weekday = weekday
        self.interval = interval
        self.occupiedRatio = occupiedRatio
        self.turnover = turnover
        self.sampleCount = sampleCount
        self.observationState = observationState
        self.observedThrough = observedThrough
    }
}

enum HistoricalObservationState: String, Codable, Hashable, Sendable {
    case observedOccupied = "observed_occupied"
    case inferredVacant = "inferred_vacant"
    case offlineOrUnobserved = "offline_or_unobserved"
    case bayNotInstalled = "bay_not_installed"
    case restrictionInactive = "restriction_inactive"
    case unknown

    var supportsNumericForecast: Bool {
        self == .observedOccupied || self == .inferredVacant
    }
}

enum ForecastEvidenceTier: String, Equatable, Sendable {
    case liveObserved
    case liveInformed
    case historical
    case demandOutlook
    case abstained
}

enum ForecastAbstentionReason: String, Equatable, Sendable {
    case missingCapacity
    case missingHistory
    case missingValidation
    case insufficientSupport
    case poorCalibration
    case staleModel
    case distributionShift
}

struct ForecastValidation: Equatable, Sendable {
    let sampleCount: Int
    let normalizedMAE: Double
    let brierScore: Double
    let intervalCoverage: Double
    let intervalRadius: Double
    let observedThrough: Date
    let modelVersion: String

    init(
        sampleCount: Int,
        normalizedMAE: Double,
        brierScore: Double,
        intervalCoverage: Double,
        intervalRadius: Double? = nil,
        observedThrough: Date,
        modelVersion: String
    ) {
        self.sampleCount = sampleCount
        self.normalizedMAE = normalizedMAE
        self.brierScore = brierScore
        self.intervalCoverage = intervalCoverage
        self.intervalRadius = intervalRadius ?? normalizedMAE
        self.observedThrough = observedThrough
        self.modelVersion = modelVersion
    }
}

struct ForecastValidationRecord: Codable, Equatable, Sendable {
    let segmentKey: String
    let sampleCount: Int
    let normalizedMAE: Double
    let brierScore: Double
    let intervalCoverage: Double
    let intervalRadius: Double?
    let observedThrough: Date
    let modelVersion: String

    var validation: ForecastValidation {
        ForecastValidation(
            sampleCount: sampleCount, normalizedMAE: normalizedMAE, brierScore: brierScore,
            intervalCoverage: intervalCoverage, intervalRadius: intervalRadius,
            observedThrough: observedThrough, modelVersion: modelVersion
        )
    }
}

struct AvailabilityPrediction: Equatable, Sendable {
    let expectedAvailable: Double?
    let lowerBound: Int?
    let upperBound: Int?
    let probabilityAtLeastOne: Double?
    let liveWeight: Double
    let evidenceTier: ForecastEvidenceTier
    let horizonMinutes: Int
    let modelVersion: String?
    let validation: ForecastValidation?
    let abstentionReason: ForecastAbstentionReason?

    var simpleLabel: String {
        guard let lowerBound, let upperBound else { return "Availability forecast unavailable" }
        if lowerBound == upperBound { return "Likely \(lowerBound) space\(lowerBound == 1 ? "" : "s")" }
        return "Likely \(lowerBound)–\(upperBound) spaces"
    }

    var chanceLabel: String {
        guard let probabilityAtLeastOne else { return "No modelled chance" }
        if probabilityAtLeastOne >= 0.75 { return "Good chance" }
        if probabilityAtLeastOne >= 0.35 { return "Some chance" }
        return "Low chance"
    }

    var hasNumericForecast: Bool {
        expectedAvailable != nil && lowerBound != nil && upperBound != nil && probabilityAtLeastOne != nil
    }
}

struct RankingCandidate: Equatable, Sendable {
    let zoneNumber: Int
    let predictedAvailable: Double
    let walkingMetres: Double
    let probabilityAtLeastOne: Double?
}

struct RankedCandidate: Equatable, Sendable {
    let zoneNumber: Int
    let score: Double
}

enum ParkingDataMode: String, Equatable, Sendable {
    case live
    case typical
}

struct ParkingZone: Identifiable, Equatable, Sendable {
    var id: Int { zoneNumber }
    let zoneNumber: Int
    let metadata: ZoneMetadata
    let available: Int
    let total: Int
    let restrictionLabel: String
    let payment: ParkingPaymentStatus
    let prediction: AvailabilityPrediction
    let walkingMetres: Double
    let newestTimestamp: Date?
    let mode: ParkingDataMode
    let schedule: [ParkingScheduleDay]
    var isBestBet: Bool

    var coordinate: Coordinate { metadata.coordinate }
}

struct ParkingRepositoryResult: Equatable, Sendable {
    let zones: [ParkingZone]
    let mode: ParkingDataMode
    let checkedAt: Date?
    let notice: String
}

struct TimedValue<Value: Sendable>: Sendable {
    let value: Value
    let storedAt: Date

    func value(ifFreshAt now: Date, ttl: TimeInterval) -> Value? {
        guard now.timeIntervalSince(storedAt) >= 0, now.timeIntervalSince(storedAt) < ttl else { return nil }
        return value
    }
}

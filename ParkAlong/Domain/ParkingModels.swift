import Foundation

struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    static let melbourneCBD = Coordinate(latitude: -37.8136, longitude: 144.9631)
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
        switch self {
        case .fifteenMinutes: "15-minute"
        case .oneHour: "1-hour"
        case .twoHours: "2-hour"
        case .threeHours: "3-hour"
        case .fourHours: "4-hour"
        case .sixHours: "6-hour"
        case .eightHours: "8-hour"
        }
    }
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
}

struct AvailabilityPrediction: Equatable, Sendable {
    let expectedAvailable: Double
    let lowerBound: Int
    let upperBound: Int
    let liveWeight: Double
    let confidence: Double

    var simpleLabel: String {
        if lowerBound == upperBound { return "Likely \(lowerBound) space\(lowerBound == 1 ? "" : "s")" }
        return "Likely \(lowerBound)–\(upperBound) spaces"
    }

    var chanceLabel: String {
        if expectedAvailable >= 3 && confidence >= 0.55 { return "Good chance" }
        if expectedAvailable >= 1 { return "Some chance" }
        return "Usually full"
    }
}

struct RankingCandidate: Equatable, Sendable {
    let zoneNumber: Int
    let predictedAvailable: Double
    let walkingMetres: Double
    let confidence: Double
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

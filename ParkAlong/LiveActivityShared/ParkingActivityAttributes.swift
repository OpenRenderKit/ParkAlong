import ActivityKit
import Foundation

struct ParkingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: ParkingActivityPhase
        var parkingTitle: String
        var locationLabel: String
        var parkingKind: ParkingActivityParkingKind
        var durationMinutes: Int
        var startedAt: Date
        var parkedAt: Date?
        var plannedDeparture: Date?
        var ruleSummary: String
        var priceSummary: String
        var availability: ParkingActivityAvailability
        var showsPreciseLocation: Bool

        var isLongStay: Bool { durationMinutes > 8 * 60 }
    }

    let sessionID: String
}

enum ParkingActivityPhase: String, Codable, Hashable {
    case enRoute
    case parked
}

enum ParkingActivityParkingKind: String, Codable, Hashable {
    case onStreet
    case offStreet
}

struct ParkingActivityAvailability: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case observed
        case estimated
        case unavailable
    }

    let kind: Kind
    let available: Int?
    let total: Int?
    let snapshotAt: Date?
    let sourceCheckedAt: Date?
}

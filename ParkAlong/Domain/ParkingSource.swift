import Foundation

enum ParkingDataClassification: String, Codable, Equatable, Sendable {
    case verifiedLive = "verified_live"
    case predicted = "predicted"
    case staticOnly = "static_only"
    case staleHistorical = "stale_historical"

    var isLive: Bool { self == .verifiedLive }
    var needsWarning: Bool { !isLive }
}

enum StaticParkingKind: String, Codable, Equatable, Sendable {
    case onStreet = "on_street"
    case offStreet = "off_street"
}

enum ParkingArchetype: String, Codable, Equatable, Sendable {
    case cbdRetail = "cbd_retail"
    case stationCommuter = "station_commuter"
    case hospitalUniversity = "hospital_university"
    case beachTourism = "beach_tourism"
    case residential = "residential"
    case events = "events"
    case general = "general"
}

struct PredictionEvidence: Codable, Equatable, Sendable {
    let sampleCount: Int
    let calibrationError: Double
    let baselineOccupiedRatio: Double
    let sourceDescription: String
    let observedThrough: Date?
}

struct ParkingSourceAttribution: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let sourceURL: URL
    let licenseName: String
    let licenseURL: URL?
    let datasetUpdatedAt: Date?
    let checkedAt: Date
}

struct ParkingSchedule: Codable, Equatable, Sendable {
    /// Foundation weekday numbers: Sunday = 1 through Saturday = 7.
    let days: [Int]
    let startMinutes: Int
    let endMinutes: Int
    let maxStayMinutes: Int?
    let restrictionText: String
    let appliesOnPublicHolidays: Bool
    let outsideWindowMeansUnrestricted: Bool
}

struct TariffTier: Codable, Equatable, Sendable {
    let upToMinutes: Int
    let priceCents: Int
}

struct ParkingTariff: Codable, Equatable, Sendable {
    let effectiveFrom: Date
    let effectiveTo: Date?
    let days: [Int]
    let startMinutes: Int
    let endMinutes: Int
    let hourlyCents: Int?
    let freeMinutes: Int
    let dailyCapCents: Int?
    let tiers: [TariffTier]
}

struct StaticParkingLocation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let municipality: String
    let coordinate: Coordinate
    let kind: StaticParkingKind
    let archetype: ParkingArchetype
    let capacity: Int?
    let accessibleSpaces: Int?
    let schedules: [ParkingSchedule]
    let tariffs: [ParkingTariff]
    let source: ParkingSourceAttribution
    let classification: ParkingDataClassification
    let predictionEvidence: PredictionEvidence?
}


import Foundation

enum ParkingOptionKind: String, Sendable {
    case onStreet = "On-street"
    case offStreet = "Off-street"
}

enum ParkingAvailabilityState: String, Sendable {
    case available
    case occupied
    case unknown
}

struct ParkingPriceInformation: Equatable, Sendable {
    let primaryText: String
    let detail: String
    let provider: String
    let actionLabel: String?
    let actionURL: URL?
}

struct ParkingOption: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ParkingOptionKind
    let title: String
    let locationLabel: String
    let coordinate: Coordinate
    let availabilityState: ParkingAvailabilityState
    let available: Int?
    let total: Int?
    let restrictionLabel: String
    let restrictionWindow: String
    let activeNow: Bool
    let price: ParkingPriceInformation
    let provider: String
    let sourceTimestamp: Date?
    let walkingMetres: Double
    let prediction: AvailabilityPrediction?
    let isBestBet: Bool
    let zoneNumber: Int?

    var availabilityLabel: String {
        if let available, let total { return "\(available) of \(total) available" }
        return availabilityState == .unknown ? "Check with provider" : availabilityState.rawValue.capitalized
    }

    static func onStreet(_ zone: ParkingZone, duration: StayDuration) -> ParkingOption {
        let price = ParkingPriceEngine.price(payment: zone.payment, duration: duration)
        return ParkingOption(
            id: "zone-\(zone.zoneNumber)", kind: .onStreet, title: zone.metadata.streetName,
            locationLabel: zone.metadata.segmentLabel, coordinate: zone.coordinate,
            availabilityState: zone.available > 0 ? .available : .occupied, available: zone.available, total: zone.total,
            restrictionLabel: zone.restrictionLabel, restrictionWindow: "Active restriction now", activeNow: true,
            price: price, provider: price.provider, sourceTimestamp: zone.newestTimestamp,
            walkingMetres: zone.walkingMetres, prediction: zone.prediction, isBestBet: zone.isBestBet, zoneNumber: zone.zoneNumber
        )
    }
}

enum ParkingPriceEngine {
    private static let cityURL = URL(string: "https://participate.melbourne.vic.gov.au/central-city-parking-review/parking-improvements")!

    static func price(payment: ParkingPaymentStatus, duration: StayDuration) -> ParkingPriceInformation {
        switch payment {
        case .free:
            return .init(primaryText: "Free", detail: "No payment indicated by the active code", provider: "City of Melbourne", actionLabel: nil, actionURL: nil)
        case .paid where duration == .fifteenMinutes:
            return .init(primaryText: "$0 first 15 min", detail: "Start a valid session; check current conditions", provider: "City of Melbourne · EasyPark", actionLabel: "Open payment information", actionURL: cityURL)
        case .paid:
            return .init(primaryText: "Check current price", detail: "Rates can vary by place and time", provider: "City of Melbourne · EasyPark", actionLabel: "Check price with provider", actionURL: cityURL)
        case .unknown:
            return .init(primaryText: "Price unknown", detail: "Check the meter and street sign", provider: "City of Melbourne", actionLabel: "Parking information", actionURL: cityURL)
        }
    }
}

enum OffStreetProviderResolver {
    static func resolve(name: String, suppliedURL: URL?) -> (provider: String, url: URL?) {
        if let suppliedURL { return (providerName(name), suppliedURL) }
        let lower = name.lowercased()
        if lower.contains("wilson") { return ("Wilson Parking", URL(string: "https://www.wilsonparking.com.au")) }
        if lower.contains("secure") { return ("Secure Parking", URL(string: "https://www.secureparking.com.au")) }
        if lower.contains("care park") { return ("Care Park", URL(string: "https://www.carepark.com.au")) }
        if lower.contains("parking24") { return ("Parking24", URL(string: "https://www.parking24.com.au")) }
        return (providerName(name), nil)
    }

    private static func providerName(_ name: String) -> String {
        name.split(separator: "-").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? name
    }
}


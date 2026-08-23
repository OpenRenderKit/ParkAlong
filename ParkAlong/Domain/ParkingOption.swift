import Foundation

enum ParkingOptionKind: String, Codable, Sendable {
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
    let classification: ParkingDataClassification
    let warningText: String?
    let sourceDatasetAt: Date?
    let sourceCheckedAt: Date?
    let schedule: [ParkingScheduleDay]
    let clusterCount: Int?
    let clusterViewport: ParkingViewport?

    var availabilityLabel: String {
        if let clusterCount { return "\(clusterCount) parking locations in this area" }
        switch classification {
        case .verifiedLive:
            if let available, let total { return "\(available) of \(total) available now" }
            return "Live availability unavailable"
        case .predicted:
            if let available, let total { return "About \(available) of \(total) typically available" }
            return "Typical demand estimate"
        case .staticOnly, .staleHistorical:
            return "Availability unknown"
        }
    }

    var pinLabel: String {
        if let clusterCount { return String(clusterCount) }
        switch classification {
        case .verifiedLive: return available.map(String.init) ?? "?"
        case .predicted: return available.map { "~\($0)" } ?? "~"
        case .staticOnly, .staleHistorical: return "P"
        }
    }

    var hasNonLiveWarning: Bool { classification.needsWarning }

    static func onStreet(_ zone: ParkingZone, plan: ParkingPlan) -> ParkingOption {
        let price = ParkingPriceEngine.price(payment: zone.payment, plan: plan, coordinate: zone.coordinate)
        let classification: ParkingDataClassification
        let available: Int?
        let warning: String?
        switch zone.prediction.evidenceTier {
        case .liveObserved:
            classification = .verifiedLive
            available = zone.available
            warning = nil
        case .liveInformed, .historical, .demandOutlook:
            classification = .predicted
            available = zone.prediction.expectedAvailable.map { Int($0.rounded(.down)) }
            warning = "Forecast based on measured historical evidence · not live at arrival"
        case .abstained:
            classification = zone.prediction.abstentionReason == .staleModel ? .staleHistorical : .staticOnly
            available = nil
            warning = "No reliable forecast for the planned arrival · current sensor counts are not reused"
        }
        let isImmediate = abs(plan.arrival.timeIntervalSinceNow) <= 5 * 60
        return ParkingOption(
            id: "zone-\(zone.zoneNumber)", kind: .onStreet, title: zone.metadata.streetName,
            locationLabel: zone.metadata.segmentLabel, coordinate: zone.coordinate,
            availabilityState: available.map { $0 > 0 ? .available : .occupied } ?? .unknown,
            available: available, total: zone.total,
            restrictionLabel: zone.restrictionLabel,
            restrictionWindow: isImmediate ? "Active restriction now" : "Rule at planned arrival",
            activeNow: isImmediate,
            price: price, provider: price.provider,
            sourceTimestamp: classification == .verifiedLive ? zone.newestTimestamp : nil,
            walkingMetres: zone.walkingMetres, prediction: zone.prediction, isBestBet: zone.isBestBet, zoneNumber: zone.zoneNumber,
            classification: classification, warningText: warning,
            sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: zone.schedule,
            clusterCount: nil, clusterViewport: nil
        )
    }
}

enum ParkingPriceEngine {
    private static let cityURL = URL(string: "https://participate.melbourne.vic.gov.au/central-city-parking-review/parking-improvements")!
    private static let melbourneTimeZone = TimeZone(identifier: "Australia/Melbourne")!

    static func price(
        payment: ParkingPaymentStatus,
        plan: ParkingPlan,
        coordinate: Coordinate
    ) -> ParkingPriceInformation {
        switch payment {
        case .free:
            return .init(primaryText: "Free", detail: "No payment indicated by the active code", provider: "City of Melbourne", actionLabel: nil, actionURL: nil)
        case .paid where isCentralMelbourneCBD(coordinate) && !plan.isPublicHoliday:
            if plan.durationMinutes <= 15 {
                return .init(
                    primaryText: "$0 for up to 15 min",
                    detail: "CBD waiver applies only when the whole EasyPark session is 15 minutes or less",
                    provider: "City of Melbourne · EasyPark",
                    actionLabel: "Open payment information", actionURL: cityURL
                )
            }
            let cents = meteredCBDCost(plan: plan)
            let total = String(format: "$%.2f", Double(cents) / 100)
            return .init(
                primaryText: "\(total) for \(plan.durationLabel)",
                detail: "$7/hr weekdays until 7 pm; $4/hr after 7 pm and weekends. Check the meter for the exact bay.",
                provider: "City of Melbourne · EasyPark",
                actionLabel: "Check current CBD rate", actionURL: cityURL
            )
        case .paid:
            return .init(primaryText: "Check current price", detail: "The active code requires payment, but no exact zone tariff is safely matched", provider: "City of Melbourne · EasyPark", actionLabel: "Check price with provider", actionURL: cityURL)
        case .unknown:
            return .init(primaryText: "Price unknown", detail: "Check the meter and street sign", provider: "City of Melbourne", actionLabel: "Parking information", actionURL: cityURL)
        }
    }

    private static func meteredCBDCost(plan: ParkingPlan) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = melbourneTimeZone
        var total = 0.0
        for minuteOffset in 0..<plan.durationMinutes {
            let date = plan.arrival.addingTimeInterval(TimeInterval(minuteOffset * 60))
            let weekday = calendar.component(.weekday, from: date)
            let hour = calendar.component(.hour, from: date)
            let isWeekdayPeak = (2...6).contains(weekday) && hour < 19
            total += Double(isWeekdayPeak ? 700 : 400) / 60
        }
        return Int(total.rounded())
    }

    private static func isCentralMelbourneCBD(_ coordinate: Coordinate) -> Bool {
        (-37.8255 ... -37.8030).contains(coordinate.latitude)
            && (144.9450 ... 144.9755).contains(coordinate.longitude)
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

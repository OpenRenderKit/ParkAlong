import Foundation

extension ParkingSession {
    init(
        id: UUID = UUID(),
        option: ParkingOption,
        plan: ParkingPlan,
        createdAt: Date = .now,
        showsPreciseLocation: Bool = false
    ) {
        self.id = id
        optionID = option.id
        parkingTitle = option.title
        locationLabel = option.locationLabel
        latitude = option.coordinate.latitude
        longitude = option.coordinate.longitude
        parkingKind = option.kind == .onStreet ? .onStreet : .offStreet
        durationMinutes = plan.durationMinutes
        intendedArrival = plan.arrival
        self.createdAt = createdAt
        ruleSummary = option.restrictionLabel
        priceSummary = option.price.primaryText
        switch option.classification {
        case .verifiedLive: availabilityKind = .observed
        case .predicted: availabilityKind = .estimated
        case .staticOnly, .staleHistorical: availabilityKind = .unavailable
        }
        available = option.available
        total = option.total
        availabilitySnapshotAt = option.sourceTimestamp
        sourceCheckedAt = option.sourceCheckedAt
        phase = .enRoute
        parkedAt = nil
        plannedDeparture = nil
        self.showsPreciseLocation = showsPreciseLocation
        reminderScheduledAt = nil
    }

    var coordinate: Coordinate { .init(latitude: latitude, longitude: longitude) }
}

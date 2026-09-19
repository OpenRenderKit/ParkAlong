import Foundation

enum ParkingActivityCopy {
    static let hiddenLocationTitle = "Parking nearby"
    static let postedSigns = "Posted signs govern"
    static let longStayLimitation =
        "This stay is longer than 8 hours. The Lock Screen card may end sooner. Keep this session in ParkAlong."
    static let reminderTitle = "Time to head back"
    static let lockScreenPrivacyTitle = "Show this place on the Lock Screen"
    static let lockScreenPrivacyHint =
        "Off by default. When on, the parking name can appear on a locked iPhone."

    static func displayTitle(for state: ParkingActivityAttributes.ContentState) -> String {
        state.showsPreciseLocation ? state.parkingTitle : hiddenLocationTitle
    }

    static func displayLocation(for state: ParkingActivityAttributes.ContentState) -> String? {
        guard state.showsPreciseLocation else { return nil }
        let label = state.locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    static func phaseTitle(_ phase: ParkingActivityPhase) -> String {
        switch phase {
        case .enRoute: "On the way"
        case .parked: "Parked"
        }
    }

    static func kindLabel(_ kind: ParkingActivityParkingKind) -> String {
        switch kind {
        case .onStreet: "On-street"
        case .offStreet: "Off-street"
        }
    }

    static func stayPhrase(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)-minute stay" }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return hours == 1 ? "1-hour stay" : "\(hours)-hour stay"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours) hr \(remainder) min stay"
    }

    static let observedAvailabilityStaleAfter: TimeInterval = 5 * 60

    static func isObservedAvailabilityStale(
        _ availability: ParkingActivityAvailability,
        now: Date = .now
    ) -> Bool {
        guard availability.kind == .observed, let snapshotAt = availability.snapshotAt else {
            return false
        }
        return now.timeIntervalSince(snapshotAt) >= observedAvailabilityStaleAfter
    }

    static func availabilityText(
        _ availability: ParkingActivityAvailability,
        isStale: Bool = false
    ) -> String {
        switch availability.kind {
        case .observed:
            let counts: String
            if let available = availability.available, let total = availability.total {
                counts = "\(available) of \(total) spaces"
            } else {
                counts = "Spaces"
            }
            let time = timestampPhrase(availability.snapshotAt ?? availability.sourceCheckedAt)
            if isStale {
                return "\(counts) observed \(time). May be out of date"
            }
            return "\(counts) observed \(time)"
        case .estimated:
            if let available = availability.available, let total = availability.total {
                return "About \(available) of \(total) typically free · estimate"
            }
            return "Availability is an estimate"
        case .unavailable:
            return "Availability unavailable"
        }
    }

    static func compactAvailability(_ availability: ParkingActivityAvailability) -> String {
        switch availability.kind {
        case .observed:
            if let available = availability.available { return "\(available)" }
            return "—"
        case .estimated:
            if let available = availability.available { return "~\(available)" }
            return "~"
        case .unavailable:
            return "P"
        }
    }

    static func compactAvailabilityAccessibility(_ availability: ParkingActivityAvailability) -> String {
        switch availability.kind {
        case .observed:
            if let available = availability.available, let total = availability.total {
                return "\(available) of \(total) spaces observed"
            }
            return "Observed availability"
        case .estimated:
            return "Estimated availability"
        case .unavailable:
            return "Availability unavailable"
        }
    }

    static func leaveByPhrase(_ date: Date) -> String {
        "Leave by \(date.formatted(date: .omitted, time: .shortened))"
    }

    static func reminderBody(departure: Date) -> String {
        "Your planned stay ends at \(departure.formatted(date: .omitted, time: .shortened)). Posted signs still govern."
    }

    private static func timestampPhrase(_ date: Date?) -> String {
        guard let date else { return "at last check" }
        return date.formatted(.relative(presentation: .named))
    }
}

extension ParkingActivityAttributes {
    static let preview = ParkingActivityAttributes(sessionID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
}

extension ParkingActivityAttributes.ContentState {
    private static let previewStart = Date(timeIntervalSince1970: 1_800_000_000)

    static let previewEnRouteObservedHidden = previewEnRoute(
        availability: .init(
            kind: .observed,
            available: 4,
            total: 7,
            snapshotAt: previewStart.addingTimeInterval(-45),
            sourceCheckedAt: previewStart.addingTimeInterval(-45)
        ),
        showsPreciseLocation: false
    )

    static let previewEnRouteObservedPrecise = previewEnRoute(
        availability: .init(
            kind: .observed,
            available: 4,
            total: 7,
            snapshotAt: previewStart.addingTimeInterval(-45),
            sourceCheckedAt: previewStart.addingTimeInterval(-45)
        ),
        showsPreciseLocation: true
    )

    static let previewEnRouteEstimated = previewEnRoute(
        availability: .init(
            kind: .estimated,
            available: 3,
            total: 7,
            snapshotAt: previewStart.addingTimeInterval(-3_600),
            sourceCheckedAt: previewStart
        ),
        showsPreciseLocation: false
    )

    static let previewEnRouteUnavailable = previewEnRoute(
        availability: .init(
            kind: .unavailable,
            available: nil,
            total: nil,
            snapshotAt: nil,
            sourceCheckedAt: previewStart
        ),
        showsPreciseLocation: false,
        parkingKind: .offStreet
    )

    static let previewParked = previewParkedState(durationMinutes: 120)

    static let previewParkedLongStay = previewParkedState(durationMinutes: 12 * 60)

    static func previewEnRoute(
        availability: ParkingActivityAvailability,
        showsPreciseLocation: Bool,
        parkingKind: ParkingActivityParkingKind = .onStreet
    ) -> Self {
        .init(
            phase: .enRoute,
            parkingTitle: "Little Collins Street",
            locationLabel: "Little Collins Street · Swanston Street to Russell Street",
            parkingKind: parkingKind,
            durationMinutes: 120,
            startedAt: previewStart,
            parkedAt: nil,
            plannedDeparture: nil,
            ruleSummary: "Up to 2 hours, meter required",
            priceSummary: "$14.00 for 2 hours",
            availability: availability,
            showsPreciseLocation: showsPreciseLocation
        )
    }

    static func previewParkedState(durationMinutes: Int) -> Self {
        let parkedAt = previewStart.addingTimeInterval(5 * 60)
        return .init(
            phase: .parked,
            parkingTitle: "Little Collins Street",
            locationLabel: "Little Collins Street · Swanston Street to Russell Street",
            parkingKind: .onStreet,
            durationMinutes: durationMinutes,
            startedAt: previewStart,
            parkedAt: parkedAt,
            plannedDeparture: parkedAt.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            ruleSummary: "Up to 2 hours, meter required",
            priceSummary: "$14.00 for 2 hours",
            availability: .init(
                kind: .observed,
                available: 4,
                total: 7,
                snapshotAt: previewStart.addingTimeInterval(-45),
                sourceCheckedAt: previewStart.addingTimeInterval(-45)
            ),
            showsPreciseLocation: true
        )
    }
}

extension ParkingSession {
    static func preview(
        phase: Phase = .enRoute,
        durationMinutes: Int = 120,
        showsPreciseLocation: Bool = false,
        availabilityKind: ParkingActivityAvailability.Kind = .observed,
        reminderScheduledAt: Date? = nil
    ) -> ParkingSession {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let parkedAt = phase == .parked ? startedAt.addingTimeInterval(5 * 60) : nil
        return ParkingSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            optionID: "zone-7002",
            parkingTitle: "Little Collins Street",
            locationLabel: "Little Collins Street · Swanston Street to Russell Street",
            latitude: -37.812,
            longitude: 144.965,
            parkingKind: .onStreet,
            durationMinutes: durationMinutes,
            intendedArrival: startedAt,
            createdAt: startedAt,
            ruleSummary: "Up to 2 hours, meter required",
            priceSummary: "$14.00 for 2 hours",
            availabilityKind: availabilityKind,
            available: availabilityKind == .unavailable ? nil : 4,
            total: availabilityKind == .unavailable ? nil : 7,
            availabilitySnapshotAt: availabilityKind == .unavailable ? nil : startedAt.addingTimeInterval(-45),
            sourceCheckedAt: startedAt.addingTimeInterval(-45),
            phase: phase,
            parkedAt: parkedAt,
            plannedDeparture: parkedAt?.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            showsPreciseLocation: showsPreciseLocation,
            reminderScheduledAt: reminderScheduledAt
        )
    }
}

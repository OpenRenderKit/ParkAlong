import Foundation

/// Single deterministic identifier shared by the app scheduler and the
/// Live Activity end intent. Defined in shared code so both targets use the
/// same string without duplicating the format.
enum ParkingReminderIdentifier {
    static func identifier(sessionID: UUID) -> String {
        "parking-reminder-\(sessionID.uuidString)"
    }
}

/// Production bound for ActivityKit content. ActivityKit rejects payloads
/// over 4 KB combined (attributes + state), and parking text originates from
/// remote/static sources. These per-field UTF-8 caps keep the worst-case
/// encoded payload well under the limit even when every byte needs JSON
/// escaping (`"` and `\` expand 1 byte to 2):
/// raw max 832 bytes -> escaped worst ~1664 + fixed overhead (~700) ~= 2.4 KB.
enum ParkingActivityContentBounds {
    static let combinedPayloadLimitBytes = 4_096
    static let parkingTitleMaxUTF8Bytes = 160
    static let locationLabelMaxUTF8Bytes = 256
    static let ruleSummaryMaxUTF8Bytes = 256
    static let priceSummaryMaxUTF8Bytes = 160

    static func sanitizedParkingTitle(_ value: String) -> String {
        sanitized(value, maxUTF8Bytes: parkingTitleMaxUTF8Bytes)
    }

    static func sanitizedLocationLabel(_ value: String) -> String {
        sanitized(value, maxUTF8Bytes: locationLabelMaxUTF8Bytes)
    }

    static func sanitizedRuleSummary(_ value: String) -> String {
        sanitized(value, maxUTF8Bytes: ruleSummaryMaxUTF8Bytes)
    }

    static func sanitizedPriceSummary(_ value: String) -> String {
        sanitized(value, maxUTF8Bytes: priceSummaryMaxUTF8Bytes)
    }

    static func sanitized(_ value: String, maxUTF8Bytes limit: Int) -> String {
        // Map controls (including \0, \n, \r, \t, DEL, C1) to spaces so
        // words do not join, then drop format/default-ignorable scalars
        // (bidi overrides, zero-width spaces, variation selectors, ZWJ).
        // Kept categories: letters, marks, numbers, punctuation, symbols,
        // and space separators. This strips adversarial invisible text while
        // preserving normal names, prices, and emoji base characters.
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) {
                scalars.append(Unicode.Scalar(0x20)!)
                continue
            }
            let properties = scalar.properties
            if properties.generalCategory == .format || properties.isDefaultIgnorableCodePoint {
                continue
            }
            scalars.append(scalar)
        }
        // Collapse all whitespace runs to a single space (also trims).
        let collapsed = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return truncatedToUTF8Bytes(collapsed, limit: limit)
    }

    private static func truncatedToUTF8Bytes(_ value: String, limit: Int) -> String {
        guard value.utf8.count > limit else { return value }
        var count = 0
        var result = ""
        for character in value {
            let bytes = String(character).utf8.count
            if count + bytes > limit { break }
            count += bytes
            result.append(character)
        }
        return result
    }
}

struct ParkingSession: Codable, Equatable, Identifiable, Sendable {
    enum Phase: String, Codable, Sendable {
        case enRoute
        case parked
    }

    let id: UUID
    let optionID: String
    let parkingTitle: String
    let locationLabel: String
    let latitude: Double
    let longitude: Double
    let parkingKind: ParkingActivityParkingKind
    let durationMinutes: Int
    let intendedArrival: Date
    let createdAt: Date
    let ruleSummary: String
    let priceSummary: String
    let availabilityKind: ParkingActivityAvailability.Kind
    let available: Int?
    let total: Int?
    let availabilitySnapshotAt: Date?
    let sourceCheckedAt: Date?
    var phase: Phase
    var parkedAt: Date?
    var plannedDeparture: Date?
    var showsPreciseLocation: Bool
    var reminderScheduledAt: Date?

    mutating func markParked(at date: Date) {
        phase = .parked
        parkedAt = date
        plannedDeparture = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    var activityState: ParkingActivityAttributes.ContentState {
        // Bound only the activity content: the stored ParkingSession keeps
        // complete remote strings, while the Live Activity copy is sanitized
        // and byte-capped so request/update never exceeds 4 KB combined.
        .init(
            phase: phase == .enRoute ? .enRoute : .parked,
            parkingTitle: ParkingActivityContentBounds.sanitizedParkingTitle(parkingTitle),
            locationLabel: ParkingActivityContentBounds.sanitizedLocationLabel(locationLabel),
            parkingKind: parkingKind,
            durationMinutes: durationMinutes,
            startedAt: createdAt,
            parkedAt: parkedAt,
            plannedDeparture: plannedDeparture,
            ruleSummary: ParkingActivityContentBounds.sanitizedRuleSummary(ruleSummary),
            priceSummary: ParkingActivityContentBounds.sanitizedPriceSummary(priceSummary),
            availability: .init(
                kind: availabilityKind,
                available: available,
                total: total,
                snapshotAt: availabilitySnapshotAt,
                sourceCheckedAt: sourceCheckedAt
            ),
            showsPreciseLocation: showsPreciseLocation
        )
    }

    var activityStaleDate: Date? {
        switch phase {
        case .enRoute:
            guard availabilityKind == .observed, let availabilitySnapshotAt else { return nil }
            return availabilitySnapshotAt.addingTimeInterval(5 * 60)
        case .parked:
            return plannedDeparture
        }
    }
}

import MapKit
import SwiftUI

enum AvailabilityStyle {
    static func color(for available: Int) -> Color {
        switch available {
        case 3...: .green
        case 1, 2: .orange
        default: .red
        }
    }

    static func accessibilityLabel(for zone: ParkingZone) -> String {
        let source = zone.mode == .live ? "live sensors" : "typical availability"
        let spaces = zone.available == 1 ? "space" : "spaces"
        return "\(zone.metadata.segmentLabel), \(zone.available) of \(zone.total) \(spaces) available, \(source)"
    }
}

extension Coordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct AvailabilityPin: View {
    let zone: ParkingZone
    var isSelected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var badgeHeight = 28.0

    var body: some View {
        let fill = AvailabilityStyle.color(for: zone.available)

        VStack(spacing: 0) {
            Text("\(zone.available)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(minWidth: 32, minHeight: badgeHeight)
                .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white, lineWidth: isSelected ? 2 : 0)
                }

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(fill)
                .offset(y: -1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 4 : 1.5, y: 1)
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isSelected)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct DestinationMarker: View {
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHidden(true)
    }
}

struct VacantBayMarker: View {
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.24), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

struct OffStreetPin: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "parkingsign")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.indigo)
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityHidden(true)
    }
}

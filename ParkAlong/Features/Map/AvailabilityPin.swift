import MapKit
import SwiftUI

enum ParkingPinPalette: Equatable {
    case liveAvailable
    case liveLimited
    case liveFull
    case predictedPlum
    case locationRed

    static let predictedPlumColor = Color(red: 107 / 255, green: 58 / 255, blue: 110 / 255)
    static let warningAmber = Color(red: 0.93, green: 0.62, blue: 0.12)

    static func live(for available: Int) -> ParkingPinPalette {
        switch available {
        case 3...: .liveAvailable
        case 1, 2: .liveLimited
        default: .liveFull
        }
    }

    var color: Color {
        switch self {
        case .liveAvailable: .green
        case .liveLimited: .orange
        case .liveFull, .locationRed: .red
        case .predictedPlum: Self.predictedPlumColor
        }
    }
}

struct ParkingPinPresentation: Equatable {
    let label: String
    let palette: ParkingPinPalette
    let showsWarning: Bool
    let accessibilityLabel: String

    init(option: ParkingOption) {
        label = option.pinLabel
        showsWarning = option.hasNonLiveWarning
        palette = Self.palette(for: option)
        accessibilityLabel = Self.accessibilityLabel(for: option)
    }

    private static func palette(for option: ParkingOption) -> ParkingPinPalette {
        switch option.classification {
        case .verifiedLive:
            ParkingPinPalette.live(for: option.available ?? 0)
        case .predicted:
            .predictedPlum
        case .staticOnly, .staleHistorical:
            .locationRed
        }
    }

    private static func accessibilityLabel(for option: ParkingOption) -> String {
        switch option.classification {
        case .verifiedLive:
            if let available = option.available, let total = option.total {
                return "\(option.title), \(available) of \(total) spaces available, live"
            }
            return "\(option.title), live"
        case .predicted:
            if let available = option.available, let total = option.total {
                return "\(option.title), about \(available) of \(total) spaces, estimate, not live"
            }
            return "\(option.title), estimate, not live"
        case .staticOnly, .staleHistorical:
            return "\(option.title), location only, not live"
        }
    }
}

enum AvailabilityStyle {
    static func color(for available: Int) -> Color {
        ParkingPinPalette.live(for: available).color
    }
}

extension Coordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct AvailabilityPin: View {
    let option: ParkingOption
    var isSelected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var badgeHeight = 28.0
    @ScaledMetric(relativeTo: .caption2) private var warningSize = 10.0

    private var presentation: ParkingPinPresentation {
        ParkingPinPresentation(option: option)
    }

    var body: some View {
        let fill = presentation.palette.color

        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text(presentation.label)
                    .font(labelFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, presentation.label.count > 2 ? 6 : 8)
                    .frame(minWidth: 30, minHeight: badgeHeight)
                    .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 1 : 0.35), lineWidth: isSelected ? 2 : 0.6)
                    }

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(fill)
                    .offset(y: -1)
            }
            .padding(.top, presentation.showsWarning ? 5 : 0)
            .padding(.trailing, presentation.showsWarning ? 5 : 0)

            if presentation.showsWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: warningSize, weight: .bold))
                    .foregroundStyle(ParkingPinPalette.warningAmber)
                    .background {
                        Circle()
                            .fill(.white)
                            .padding(-1.5)
                    }
                    .accessibilityHidden(true)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 2.5 : 1, y: 1)
        .scaleEffect(isSelected ? 1.1 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isSelected)
        .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var labelFont: Font {
        presentation.palette == .locationRed
            ? .caption.weight(.heavy)
            : .caption.weight(.bold).monospacedDigit()
    }
}

struct ParkingPinButton: View {
    let option: ParkingOption
    var isSelected = false
    let identifier: String
    var hint = "Shows parking details"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            AvailabilityPin(option: option, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityLabel(ParkingPinPresentation(option: option).accessibilityLabel)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

struct DestinationMarker: View {
    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
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
            .accessibilityHidden(true)
    }
}

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

enum ParkingActivityPalette {
    static let plum = Color(red: 107 / 255, green: 58 / 255, blue: 110 / 255)
    static let amber = Color(red: 0.93, green: 0.62, blue: 0.12)
}

struct ParkingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ParkingActivityAttributes.self) { context in
            ParkingActivityLockScreenView(
                state: context.state,
                isStale: context.isStale,
                sessionID: context.attributes.sessionID
            )
            .widgetURL(ParkingSessionDeepLink.url(sessionIDString: context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ParkingActivityPhaseMark(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ParkingActivityCompactMetric(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    ParkingActivityExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ParkingActivityExpandedBottom(
                        state: context.state,
                        isStale: context.isStale,
                        sessionID: context.attributes.sessionID
                    )
                }
            } compactLeading: {
                ParkingActivityCompactLeading(state: context.state)
            } compactTrailing: {
                ParkingActivityCompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                ParkingActivityMinimal(state: context.state)
            }
            .widgetURL(ParkingSessionDeepLink.url(sessionIDString: context.attributes.sessionID))
            .keylineTint(context.state.phase == .parked ? .green : ParkingActivityPalette.plum)
        }
    }
}

struct ParkingActivityLockScreenView: View {
    let state: ParkingActivityAttributes.ContentState
    var isStale = false
    let sessionID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ParkingActivityPhaseMark(state: state)
                Spacer(minLength: 8)
                if state.phase == .parked, let departure = state.plannedDeparture {
                    Text(departure, style: .timer)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityLabel("Time left in planned stay")
                } else {
                    Text(ParkingActivityCopy.stayPhrase(minutes: state.durationMinutes))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            identity

            if state.phase == .enRoute {
                Text(ParkingActivityCopy.availabilityText(state.availability, isStale: isStale))
                    .font(.footnote)
                    .foregroundStyle(availabilityColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(ParkingActivityCopy.availabilityText(state.availability, isStale: isStale))
            } else {
                parkedFacts
            }

            ParkingActivityActions(state: state, sessionID: sessionID, compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(ParkingActivityPalette.plum.opacity(0.16))
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ParkingActivityCopy.displayTitle(for: state))
                .font(.headline)
                .lineLimit(1)
                .privacySensitive(state.showsPreciseLocation)
            if let location = ParkingActivityCopy.displayLocation(for: state) {
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lockScreenIdentityLabel)
    }

    @ViewBuilder
    private var parkedFacts: some View {
        if let departure = state.plannedDeparture {
            Text(ParkingActivityCopy.leaveByPhrase(departure))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        if knownContextAvailable {
            Text(lockScreenContext)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        Text(ParkingActivityCopy.postedSigns)
            .font(.caption.weight(.semibold))
        if state.isLongStay {
            Text(ParkingActivityCopy.longStayLimitation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var knownContextAvailable: Bool {
        !state.ruleSummary.isEmpty || !state.priceSummary.isEmpty
    }

    private var lockScreenContext: String {
        [state.ruleSummary, state.priceSummary]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var lockScreenIdentityLabel: String {
        var parts = [
            ParkingActivityCopy.phaseTitle(state.phase),
            ParkingActivityCopy.displayTitle(for: state)
        ]
        if let location = ParkingActivityCopy.displayLocation(for: state) {
            parts.append(location)
        }
        return parts.joined(separator: ", ")
    }

    private var availabilityColor: Color {
        switch state.availability.kind {
        case .observed: isStale ? ParkingActivityPalette.amber : .green
        case .estimated: ParkingActivityPalette.plum
        case .unavailable: .secondary
        }
    }
}

struct ParkingActivityPhaseMark: View {
    let state: ParkingActivityAttributes.ContentState

    var body: some View {
        Label(ParkingActivityCopy.phaseTitle(state.phase), systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.phase == .parked ? .green : ParkingActivityPalette.plum)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(ParkingActivityCopy.phaseTitle(state.phase))
    }

    private var icon: String {
        state.phase == .parked ? "parkingsign.circle.fill" : "car.fill"
    }
}

struct ParkingActivityExpandedCenter: View {
    let state: ParkingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ParkingActivityCopy.displayTitle(for: state))
                .font(.headline)
                .lineLimit(1)
                .privacySensitive(state.showsPreciseLocation)
            Text(ParkingActivityCopy.kindLabel(state.parkingKind))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ParkingActivityExpandedBottom: View {
    let state: ParkingActivityAttributes.ContentState
    var isStale = false
    let sessionID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.phase == .enRoute {
                Text(ParkingActivityCopy.availabilityText(state.availability, isStale: isStale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let departure = state.plannedDeparture {
                        Text(ParkingActivityCopy.leaveByPhrase(departure))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    if !state.ruleSummary.isEmpty {
                        Text(state.ruleSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(ParkingActivityCopy.postedSigns)
                    .font(.caption.weight(.semibold))
            }
            ParkingActivityActions(state: state, sessionID: sessionID, compact: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ParkingActivityCompactLeading: View {
    let state: ParkingActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.phase == .parked ? "parkingsign.circle.fill" : "car.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(state.phase == .parked ? .green : ParkingActivityPalette.plum)
            .accessibilityLabel(ParkingActivityCopy.phaseTitle(state.phase))
    }
}

struct ParkingActivityCompactTrailing: View {
    let state: ParkingActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        ParkingActivityCompactMetric(state: state, isStale: isStale)
    }
}

struct ParkingActivityMinimal: View {
    let state: ParkingActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.phase == .parked ? "parkingsign.circle.fill" : "car.fill")
            .foregroundStyle(state.phase == .parked ? .green : ParkingActivityPalette.plum)
            .accessibilityLabel(ParkingActivityCopy.phaseTitle(state.phase))
    }
}

struct ParkingActivityCompactMetric: View {
    let state: ParkingActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        if state.phase == .parked, let departure = state.plannedDeparture {
            Text(departure, style: .timer)
                .font(.caption.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel("Time left in planned stay")
        } else {
            Text(ParkingActivityCopy.compactAvailability(state.availability))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(metricColor)
                .accessibilityLabel(ParkingActivityCopy.compactAvailabilityAccessibility(state.availability))
        }
    }

    private var metricColor: Color {
        switch state.availability.kind {
        case .observed: isStale ? ParkingActivityPalette.amber : .green
        case .estimated: ParkingActivityPalette.plum
        case .unavailable: .secondary
        }
    }
}

struct ParkingActivityActions: View {
    let state: ParkingActivityAttributes.ContentState
    let sessionID: String
    var compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if state.phase == .enRoute {
                Button(intent: MarkParkedIntent(sessionID: sessionID)) {
                    actionLabel("I'm parked", systemImage: "parkingsign")
                }
                .tint(.green)
                .accessibilityHint("Records that you parked. ParkAlong does not detect arrival.")
            } else {
                if let url = ParkingSessionDeepLink.url(sessionIDString: sessionID, action: .returnToCar) {
                    Link(destination: url) {
                        actionLabel("Return to car", systemImage: "figure.walk")
                    }
                    .accessibilityHint("Opens walking directions in Apple Maps")
                }
                Button(intent: EndParkingIntent(sessionID: sessionID)) {
                    actionLabel("End", systemImage: "xmark")
                }
                .tint(.red)
                .accessibilityHint("Clears this parking session")
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 36 : 44)
            .contentShape(Rectangle())
    }
}

#Preview("Lock Screen en route, hidden", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteObservedHidden
}

#Preview("Lock Screen en route, precise", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteObservedPrecise
}

#Preview("Lock Screen estimate", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteEstimated
}

#Preview("Lock Screen unavailable", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteUnavailable
}

#Preview("Lock Screen parked", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewParked
}

#Preview("Lock Screen long stay", as: .content, using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewParkedLongStay
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteObservedHidden
    ParkingActivityAttributes.ContentState.previewParked
}

#Preview("Island expanded en route", as: .dynamicIsland(.expanded), using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteObservedPrecise
    ParkingActivityAttributes.ContentState.previewEnRouteEstimated
    ParkingActivityAttributes.ContentState.previewEnRouteUnavailable
}

#Preview("Island expanded parked", as: .dynamicIsland(.expanded), using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewParked
    ParkingActivityAttributes.ContentState.previewParkedLongStay
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: ParkingActivityAttributes.preview) {
    ParkingLiveActivity()
} contentStates: {
    ParkingActivityAttributes.ContentState.previewEnRouteObservedHidden
    ParkingActivityAttributes.ContentState.previewParked
}

#Preview("Lock Screen view, stale observed") {
    ParkingActivityLockScreenView(
        state: .previewEnRouteObservedHidden,
        isStale: true,
        sessionID: ParkingActivityAttributes.preview.sessionID
    )
}

#Preview("Compact leading and trailing") {
    HStack(spacing: 12) {
        ParkingActivityCompactLeading(state: .previewEnRouteEstimated)
        ParkingActivityCompactTrailing(state: .previewEnRouteEstimated)
        Divider()
        ParkingActivityCompactLeading(state: .previewParked)
        ParkingActivityCompactTrailing(state: .previewParked)
    }
    .padding()
}

#Preview("Minimal") {
    HStack(spacing: 16) {
        ParkingActivityMinimal(state: .previewEnRouteUnavailable)
        ParkingActivityMinimal(state: .previewParked)
    }
    .padding()
}

#Preview("Expanded bottom parked") {
    ParkingActivityExpandedBottom(
        state: .previewParked,
        sessionID: ParkingActivityAttributes.preview.sessionID
    )
    .padding()
}

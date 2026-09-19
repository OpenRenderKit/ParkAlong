import SwiftUI

struct ParkingSessionView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Group {
                if let session = viewModel.parkingSession {
                    ParkingSessionContent(
                        session: session,
                        liveActivityOutcome: viewModel.liveActivityStartOutcome,
                        reminderOutcome: viewModel.reminderScheduleOutcome,
                        navigationWasIntercepted: viewModel.navigationWasIntercepted,
                        navigationHandoffFailed: viewModel.navigationHandoffFailed,
                        dynamicTypeSize: dynamicTypeSize,
                        onMarkParked: { Task { await viewModel.markParked() } },
                        onReturnToCar: { viewModel.returnToParking() },
                        onEndSession: { Task { await viewModel.endParkingSession() } },
                        onTogglePreciseLocation: { showsPrecise in
                            Task { await viewModel.setShowsPreciseLocation(showsPrecise) }
                        },
                        onScheduleReminder: {
                            Task { await viewModel.scheduleParkingReminder(message: reminderMessage(for: session)) }
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "No parking session",
                        systemImage: "parkingsign",
                        description: Text("Start from Navigate when you pick a place to park.")
                    )
                    .accessibilityIdentifier("parking-session-empty")
                }
            }
            .navigationTitle("Parking session")
            .navigationBarTitleDisplayMode(.inline)
        }
        .adaptiveToolbarMinimizationBehavior()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("parking-session-sheet")
    }

    private func reminderMessage(for session: ParkingSession) -> ParkingReminderMessage {
        let departure = session.plannedDeparture ?? Date.now
        return ParkingReminderMessage(
            title: ParkingActivityCopy.reminderTitle,
            body: ParkingActivityCopy.reminderBody(departure: departure)
        )
    }
}

struct ParkingSessionContent: View {
    let session: ParkingSession
    let liveActivityOutcome: ParkingLiveActivityStartOutcome?
    let reminderOutcome: ParkingReminderScheduleOutcome?
    let navigationWasIntercepted: Bool
    let navigationHandoffFailed: Bool
    var dynamicTypeSize: DynamicTypeSize = .large
    var onMarkParked: () -> Void = {}
    var onReturnToCar: () -> Void = {}
    var onEndSession: () -> Void = {}
    var onTogglePreciseLocation: (Bool) -> Void = { _ in }
    var onScheduleReminder: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                liveActivityBanner
                planCard
                if session.phase == .enRoute {
                    availabilityCard
                } else {
                    parkedCard
                }
                contextCard
                privacyCard
                if session.phase == .parked {
                    reminderCard
                }
                Text(ParkingActivityCopy.postedSigns)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("posted-signs-govern")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) { actions }
    }

    private var liveActivityBanner: some View {
        let status = ParkingSessionStatusCopy.liveActivity(liveActivityOutcome)
        return Text(status.text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                status.isFallback
                    ? ParkingPinPalette.warningAmber.opacity(0.18)
                    : Color.green.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        status.isFallback ? ParkingPinPalette.warningAmber.opacity(0.55) : Color.green.opacity(0.4),
                        lineWidth: 1
                    )
            }
            .accessibilityIdentifier(status.isFallback ? "live-activity-fallback-status" : "live-activity-status")
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ParkingActivityCopy.phaseTitle(session.phase == .parked ? .parked : .enRoute).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(session.phase == .parked ? .green : ParkingPinPalette.predictedPlumColor)
            Text(session.parkingTitle)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("parking-session-title")
            Label(session.locationLabel, systemImage: "location.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(ParkingActivityCopy.kindLabel(session.parkingKind)) · \(ParkingActivityCopy.stayPhrase(minutes: session.durationMinutes))")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("parking-session-plan")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVAILABILITY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(ParkingActivityCopy.availabilityText(
                session.activityState.availability,
                isStale: isAvailabilityStale
            ))
                .font(.title3.weight(.bold))
                .foregroundStyle(availabilityColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("parking-session-availability")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var parkedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLANNED STAY")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let departure = session.plannedDeparture {
                Text(departure, style: .timer)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel("Time left in planned stay")
                    .accessibilityIdentifier("parking-session-countdown")
                Text(ParkingActivityCopy.leaveByPhrase(departure))
                    .font(.headline)
                    .accessibilityIdentifier("parking-session-departure")
            } else {
                Text("Planned departure isn’t set yet.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if session.activityState.isLongStay {
                Text(ParkingActivityCopy.longStayLimitation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("long-stay-limitation")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !session.ruleSummary.isEmpty {
                labeledRow("RULE", session.ruleSummary, identifier: "parking-session-rule")
            }
            if !session.priceSummary.isEmpty {
                labeledRow("PRICE", session.priceSummary, identifier: "parking-session-price")
            }
            if session.ruleSummary.isEmpty && session.priceSummary.isEmpty {
                Text("No verified rule or price for this place. Check the sign.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("parking-session-context-empty")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: privacyBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ParkingActivityCopy.lockScreenPrivacyTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ParkingActivityCopy.lockScreenPrivacyHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(ParkingPinPalette.predictedPlumColor)
            .accessibilityIdentifier("show-lock-screen-location-toggle")
            .accessibilityHint(ParkingActivityCopy.lockScreenPrivacyHint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onScheduleReminder) {
                Label(
                    session.reminderScheduledAt == nil ? "Remind me before this stay ends" : "Reminder already set",
                    systemImage: "bell"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(session.reminderScheduledAt != nil)
            .accessibilityIdentifier("set-reminder-button")
            .accessibilityHint("Sets a local reminder before the planned departure. This is not a meter session.")
            if let status = ParkingSessionStatusCopy.reminder(reminderOutcome, scheduledAt: session.reminderScheduledAt) {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(reminderColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("parking-reminder-status")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if session.phase == .enRoute {
                Button(action: onMarkParked) {
                    Label("I'm parked", systemImage: "parkingsign")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .adaptiveProminentAction()
                .controlSize(.large)
                .tint(.green)
                .accessibilityIdentifier("mark-parked-button")
                .accessibilityHint("Records that you parked. ParkAlong does not detect arrival.")
            } else {
                Button(action: onReturnToCar) {
                    Label("Return to car", systemImage: "figure.walk")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .adaptiveProminentAction()
                .controlSize(.large)
                .accessibilityIdentifier("return-to-car-button")
                .accessibilityHint("Opens walking directions in Apple Maps")
            }

            Button(role: .destructive, action: onEndSession) {
                Text("End session")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("end-parking-button")
            .accessibilityHint("Clears this parking session")

            if navigationHandoffFailed {
                Text("Apple Maps couldn’t open. Try again.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("navigation-handoff-failed")
            } else if navigationWasIntercepted {
                Text(session.phase == .parked ? "Walking directions ready" : "Navigation handoff ready")
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier(
                        session.phase == .parked ? "return-navigation-intercepted" : "navigation-intercepted"
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var privacyBinding: Binding<Bool> {
        Binding(
            get: { session.showsPreciseLocation },
            set: { newValue in
                onTogglePreciseLocation(newValue)
            }
        )
    }

    private var isAvailabilityStale: Bool {
        ParkingActivityCopy.isObservedAvailabilityStale(session.activityState.availability)
    }

    private var availabilityColor: Color {
        switch session.availabilityKind {
        case .observed: isAvailabilityStale ? ParkingPinPalette.warningAmber : .green
        case .estimated: ParkingPinPalette.predictedPlumColor
        case .unavailable: .primary
        }
    }

    private var reminderColor: Color {
        switch reminderOutcome {
        case .scheduled, nil:
            .primary
        case .denied, .tooLate, .unavailable:
            ParkingPinPalette.warningAmber
        }
    }

    private func labeledRow(_ title: String, _ value: String, identifier: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(value)
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier)
                }
            }
        }
    }
}

enum ParkingSessionStatusCopy {
    static func liveActivity(_ outcome: ParkingLiveActivityStartOutcome?) -> (text: String, isFallback: Bool) {
        switch outcome {
        case .started:
            ("Parking card is on the Lock Screen. Apple Maps has the route.", false)
        case .disabled:
            ("Lock Screen cards are off. Keep this session in ParkAlong.", true)
        case .unavailable:
            ("A Lock Screen card isn’t available. Keep this session in ParkAlong.", true)
        case nil:
            ("Keep this session in ParkAlong.", true)
        }
    }

    static func reminder(_ outcome: ParkingReminderScheduleOutcome?, scheduledAt: Date?) -> String? {
        if let outcome {
            switch outcome {
            case let .scheduled(date):
                return "Reminder set for \(date.formatted(date: .omitted, time: .shortened))"
            case .denied:
                return "Notifications are off, so ParkAlong can’t remind you"
            case .tooLate:
                return "Too late to remind before this stay ends"
            case .unavailable:
                return "A reminder couldn’t be set right now"
            }
        }
        if let scheduledAt {
            return "Reminder set for \(scheduledAt.formatted(date: .omitted, time: .shortened))"
        }
        return nil
    }
}

struct ParkingSessionMapEntry: View {
    @Bindable var viewModel: ParkingMapViewModel

    var body: some View {
        if let session = viewModel.parkingSession, !viewModel.isParkingSessionPresented {
            Button(action: viewModel.presentParkingSession) {
                HStack(spacing: 10) {
                    Image(systemName: session.phase == .parked ? "parkingsign.circle.fill" : "car.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(session.phase == .parked ? .green : ParkingPinPalette.predictedPlumColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ParkingActivityCopy.phaseTitle(session.phase == .parked ? .parked : .enRoute))
                            .font(.caption.weight(.semibold))
                        Text(session.parkingTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveGlassSurface(cornerRadius: 18, isInteractive: true)
            .accessibilityLabel(
                "\(ParkingActivityCopy.phaseTitle(session.phase == .parked ? .parked : .enRoute)), \(session.parkingTitle)"
            )
            .accessibilityHint("Shows the parking session")
            .accessibilityIdentifier("parking-session-chip")
        }
    }
}

#Preview("En route fallback") {
    ParkingSessionContent(
        session: .preview(availabilityKind: .observed),
        liveActivityOutcome: .disabled,
        reminderOutcome: nil,
        navigationWasIntercepted: true,
        navigationHandoffFailed: false,
        onMarkParked: {},
        onReturnToCar: {},
        onEndSession: {},
        onTogglePreciseLocation: { _ in },
        onScheduleReminder: {}
    )
}

#Preview("Parked with reminder") {
    ParkingSessionContent(
        session: .preview(phase: .parked, showsPreciseLocation: true, reminderScheduledAt: Date().addingTimeInterval(40 * 60)),
        liveActivityOutcome: .started,
        reminderOutcome: .scheduled(Date().addingTimeInterval(40 * 60)),
        navigationWasIntercepted: false,
        navigationHandoffFailed: false,
        onMarkParked: {},
        onReturnToCar: {},
        onEndSession: {},
        onTogglePreciseLocation: { _ in },
        onScheduleReminder: {}
    )
}

#Preview("Long stay estimate") {
    ParkingSessionContent(
        session: .preview(phase: .parked, durationMinutes: 12 * 60, availabilityKind: .estimated),
        liveActivityOutcome: .unavailable,
        reminderOutcome: .unavailable,
        navigationWasIntercepted: false,
        navigationHandoffFailed: true,
        onMarkParked: {},
        onReturnToCar: {},
        onEndSession: {},
        onTogglePreciseLocation: { _ in },
        onScheduleReminder: {}
    )
}

#Preview("Unavailable availability") {
    ParkingSessionContent(
        session: .preview(availabilityKind: .unavailable),
        liveActivityOutcome: .started,
        reminderOutcome: nil,
        navigationWasIntercepted: false,
        navigationHandoffFailed: false,
        onMarkParked: {},
        onReturnToCar: {},
        onEndSession: {},
        onTogglePreciseLocation: { _ in },
        onScheduleReminder: {}
    )
}

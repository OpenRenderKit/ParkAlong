import SwiftUI
import UIKit

struct MapTopChrome: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var showingAbout: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            searchButton
            ChromeIconButton(
                systemName: viewModel.destination.id == "current" ? "location.fill" : "location",
                accessibilityLabel: "Use current location",
                identifier: "current-location-button"
            ) {
                Task { await viewModel.useCurrentLocation() }
            }
            .accessibilityValue(viewModel.destination.id == "current" ? "selected" : "not selected")

            ChromeIconButton(
                systemName: "info.circle",
                accessibilityLabel: "About ParkAlong",
                identifier: "about-parkalong-button"
            ) {
                showingAbout = true
            }
        }
        .padding(6)
        .adaptiveGlassSurface(cornerRadius: 22, isInteractive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("destination-search-container")
    }

    private var searchButton: some View {
        Button {
            viewModel.isSearching = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.destination.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.85)
                        .accessibilityIdentifier("destination-title")

                    if !viewModel.destination.subtitle.isEmpty {
                        Text(viewModel.destination.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search destination, \(viewModel.destination.name)")
        .accessibilityIdentifier("destination-search-button")
    }
}

struct MapBottomChrome: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var showingPlanner: Bool
    @Binding var restorePlannerButtonFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 10) {
            statusIsland
            if viewModel.selectedOption == nil, let suggested = viewModel.zones.first(where: \.isSuggested) {
                SuggestedOnStreetAreaButton(option: .onStreet(suggested, plan: viewModel.plan)) {
                    Task { await viewModel.selectZone(suggested) }
                }
            }
            if viewModel.selectedOption == nil {
                StayDurationBar(
                    viewModel: viewModel,
                    showingPlanner: $showingPlanner,
                    restorePlannerButtonFocus: $restorePlannerButtonFocus
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("parking-action-dock")
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: viewModel.state)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: viewModel.selectedZone?.zoneNumber)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: viewModel.canRecoverLocationFromSettings)
    }

    @ViewBuilder
    private var statusIsland: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(hasVisiblePins ? "Updating visible parking" : "Checking availability")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .adaptiveGlassSurface(cornerRadius: 22)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("availability-loading")
            .accessibilityLabel(hasVisiblePins ? "Updating visible parking" : "Checking availability")
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("availability-error")

                Button("Try Again") {
                    Task { await viewModel.refresh(force: true) }
                }
                .font(.subheadline.weight(.semibold))
                .adaptiveProminentAction()
                .controlSize(.regular)
                .frame(minHeight: 44)
                .accessibilityIdentifier("retry-button")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .adaptiveGlassSurface(cornerRadius: 18)
        case .loaded:
            if viewModel.canRecoverLocationFromSettings, viewModel.selectedZone == nil {
                locationSettingsRecovery
            } else if viewModel.selectedZone == nil {
                Text(statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .adaptiveGlassSurface(cornerRadius: 16)
                    .accessibilityLabel(statusText)
                    .accessibilityIdentifier("availability-status")
            }
        }
    }

    private var locationSettingsRecovery: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    locationDeniedMessage
                    openSettingsButton
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    locationDeniedMessage
                    openSettingsButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .adaptiveGlassSurface(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("location-settings-recovery")
    }

    private var locationDeniedMessage: some View {
        Text("Showing Melbourne CBD because ParkAlong can’t use your location.")
            .font(.footnote)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("location-denied-status")
    }

    private var openSettingsButton: some View {
        Button("Open Settings") {
            openParkAlongSettings()
        }
        .font(.subheadline.weight(.semibold))
        .adaptiveProminentAction()
        .controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityLabel("Open Settings")
        .accessibilityHint("Opens ParkAlong settings so you can allow location.")
        .accessibilityIdentifier("open-location-settings-button")
    }

    private func openParkAlongSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var hasVisiblePins: Bool {
        !viewModel.mapZones.isEmpty || !viewModel.staticOptions.isEmpty || !viewModel.offStreetOptions.isEmpty
    }

    private var statusText: String {
        if !viewModel.notice.isEmpty { return viewModel.notice }
        let arrival = StayPlanFormatting.arrivalCaption(for: viewModel.plan)
        switch viewModel.mode {
        case .live:
            if let checkedAt = viewModel.checkedAt {
                return "Live · checked \(checkedAt.formatted(date: .omitted, time: .shortened))\(arrival.map { " · \($0)" } ?? "")"
            }
            return "Live sensor availability\(arrival.map { " · \($0)" } ?? "")"
        case .typical:
            return "Typical availability · live sensors unavailable\(arrival.map { " · \($0)" } ?? "")"
        }
    }
}

struct SuggestedOnStreetAreaButton: View {
    let option: ParkingOption
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Suggested street parking", systemImage: "star.fill")
                                .font(.headline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text(option.pinLabel)
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        Text(option.title)
                            .font(.headline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.footnote.weight(.bold))
                            .symbolRenderingMode(.monochrome)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Suggested street parking")
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(option.pinLabel)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .frame(minWidth: 28)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
        }
        .adaptiveProminentAction()
        .buttonBorderShape(.roundedRectangle)
        .controlSize(.large)
        .tint(ParkingPinPresentation(option: option).palette.color)
        .accessibilityLabel(Self.accessibilityText(for: option))
        .accessibilityHint("Opens details for this suggested street parking. This is not a guarantee.")
        .accessibilityIdentifier("suggested-on-street-area-button")
        .sensoryFeedback(.selection, trigger: option.zoneNumber ?? 0)
    }

    static func accessibilityText(for option: ParkingOption) -> String {
        "Suggested street parking, \(option.title), \(option.availabilityLabel). This is a suggestion, not a guarantee."
    }
}

struct StayDurationBar: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var showingPlanner: Bool
    @Binding var restorePlannerButtonFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isPlannerButtonFocused: Bool

    private var trackShape: Capsule {
        Capsule(style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = StayPlanFormatting.arrivalCaption(for: viewModel.plan) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("planned-arrival-caption")
            }

            AdaptiveGlassContainer(spacing: 8) {
                VStack(spacing: 8) {
                    stayTrack

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        plannerButton
                        refreshButton
                    }
                }
                .adaptiveControlDock(cornerRadius: 22)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.plan)
        .sensoryFeedback(.selection, trigger: viewModel.plan.durationMinutes)
        .onAppear {
            guard restorePlannerButtonFocus else { return }
            restorePlannerButtonFocus = false
            isPlannerButtonFocused = true
        }
    }

    private var stayTrack: some View {
        Picker("Stay duration", selection: durationSelection) {
            ForEach(StayTrackItem.all) { item in
                Text(chipLabel(for: item, selected: selectedItem == item))
                    .tag(item)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityIdentifier(item.identifier)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.extraLarge)
        .labelsHidden()
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityIdentifier("stay-duration-picker")
        .padding(2)
        .adaptiveGlassSurface(shape: trackShape, isInteractive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stay-duration-track")
    }

    private var plannerButton: some View {
        Button {
            showingPlanner = true
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .adaptiveGlassControlButton()
        .accessibilityLabel("Arrival and stay planner")
        .accessibilityIdentifier("arrival-planner-button")
        .accessibilityFocused($isPlannerButtonFocused)
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refresh(force: true) }
        } label: {
            Group {
                if case .loading = viewModel.state {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .adaptiveGlassControlButton()
        .disabled({
            if case .loading = viewModel.state { return true }
            return false
        }())
        .accessibilityLabel("Refresh availability")
        .accessibilityIdentifier("refresh-availability-button")
    }

    private var selectedItem: StayTrackItem {
        StayTrackItem.matching(durationMinutes: viewModel.plan.durationMinutes)
    }

    private var durationSelection: Binding<StayTrackItem> {
        Binding(
            get: { selectedItem },
            set: { select($0) }
        )
    }

    private func chipLabel(for item: StayTrackItem, selected: Bool) -> String {
        if item == .extended, selected, !StayTrackItem.presetMinutes.contains(viewModel.plan.durationMinutes) {
            return StayPlanFormatting.compactDuration(viewModel.plan.durationMinutes)
        }
        return item.shortLabel
    }

    private func select(_ item: StayTrackItem) {
        switch item {
        case .minutes(let minutes):
            viewModel.applyPlan(
                ParkingPlan(
                    arrival: viewModel.plan.arrival,
                    durationMinutes: minutes,
                    isPublicHoliday: viewModel.plan.isPublicHoliday
                )
            )
        case .extended:
            viewModel.applyPlan(
                ParkingPlan(
                    arrival: viewModel.plan.arrival,
                    duration: .eightHours,
                    isPublicHoliday: viewModel.plan.isPublicHoliday
                )
            )
        }
    }

}

private enum StayTrackItem: Hashable, Identifiable {
    case minutes(Int)
    case extended

    static let presetMinutes = [15, 60, 120, 180, 240, 360]
    static let presets = presetMinutes.map(StayTrackItem.minutes)
    static let all = presets + [.extended]

    var id: String { identifier }

    var shortLabel: String {
        switch self {
        case .minutes(15): "15m"
        case .minutes(60): "1h"
        case .minutes(120): "2h"
        case .minutes(180): "3h"
        case .minutes(240): "4h"
        case .minutes(360): "6h"
        case .extended: "8h+"
        default: "Stay"
        }
    }

    var identifier: String {
        switch self {
        case .extended: "duration-8h+"
        case .minutes: "duration-\(shortLabel)"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .minutes(15): "15 minutes"
        case .minutes(60): "1 hour"
        case .minutes(120): "2 hours"
        case .minutes(180): "3 hours"
        case .minutes(240): "4 hours"
        case .minutes(360): "6 hours"
        case .extended: "8 hours"
        default: "Stay duration"
        }
    }

    static func matching(durationMinutes: Int) -> StayTrackItem {
        presetMinutes.contains(durationMinutes) ? .minutes(durationMinutes) : .extended
    }
}

enum StayPlanFormatting {
    static func arrivalCaption(for plan: ParkingPlan) -> String? {
        guard abs(plan.arrival.timeIntervalSinceNow) > 5 * 60 else { return nil }
        let arrival = plan.arrival.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "For arrival \(arrival) · \(plan.durationLabel)"
    }

    static func compactDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes.isMultiple(of: 24 * 60) { return "\(minutes / (24 * 60))d" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)h" }
        return ParkingPlan.durationLabel(minutes: minutes)
    }
}

struct ArrivalStayPlannerView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var isPresented: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isPlannerFocused: Bool
    @State private var arrival: Date
    @State private var durationMinutes: Int
    private let isPublicHoliday: Bool

    private static let victoriaTimeZone = TimeZone(identifier: "Australia/Melbourne") ?? .current
    private static let maximumMinutes = 7 * 24 * 60

    init(viewModel: ParkingMapViewModel, isPresented: Binding<Bool>, preferEightHourDefault: Bool) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        let plan = viewModel.plan
        let minutes = preferEightHourDefault && plan.durationMinutes < 480 ? 480 : plan.durationMinutes
        _arrival = State(initialValue: Self.rounded(plan.arrival))
        _durationMinutes = State(initialValue: minutes)
        isPublicHoliday = plan.isPublicHoliday
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Results use this planned arrival, not the current time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("planner-arrival-context")
                }

                Section("Arrival") {
                    dayButtons
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

                    DatePicker(
                        "Arrival date and time",
                        selection: $arrival,
                        in: Self.startOfToday...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, Self.victoriaTimeZone)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("planner-arrival-date")
                }

                Section("Stay") {
                    presetGrid
                    durationSteppers
                    Text(ParkingPlan.durationLabel(minutes: durationMinutes))
                        .font(.headline)
                        .accessibilityIdentifier("planner-duration-value")
                    if let overnight = overnightSummary {
                        Text(overnight)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("planner-overnight-summary")
                    }
                }
            }
            .navigationTitle("Arrival and Stay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { discardAndClose() }
                        .keyboardShortcut(.cancelAction)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityHint("Closes without changing the current stay")
                        .accessibilityInputLabels(["Close", "Cancel"])
                        .accessibilityIdentifier("planner-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .adaptiveToolbarMinimizationBehavior()
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .environment(\.timeZone, Self.victoriaTimeZone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arrival-stay-planner")
        .accessibilityAction(.escape, discardAndClose)
        .accessibilityFocused($isPlannerFocused)
        .onAppear { isPlannerFocused = true }
        .simultaneousGesture(backSwipe)
    }

    @ViewBuilder
    private var dayButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                dayButton("Today", identifier: "planner-arrival-today") {
                    arrival = Self.rounded(.now)
                }
                dayButton("Tomorrow", identifier: "planner-arrival-tomorrow") {
                    arrival = Self.tomorrow(preserving: arrival)
                }
            }
        } else {
            HStack(spacing: 8) {
                dayButton("Today", identifier: "planner-arrival-today") {
                    arrival = Self.rounded(.now)
                }
                dayButton("Tomorrow", identifier: "planner-arrival-tomorrow") {
                    arrival = Self.tomorrow(preserving: arrival)
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    resetButton
                    applyButton
                }
            } else {
                HStack(spacing: 12) {
                    resetButton
                    applyButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var resetButton: some View {
        Button("Reset") {
            arrival = Self.rounded(.now)
            durationMinutes = StayDuration.oneHour.rawValue
            applyAndClose()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityIdentifier("planner-reset")
    }

    private var applyButton: some View {
        Button("Apply") {
            applyAndClose()
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 44)
        .adaptiveProminentAction()
        .accessibilityIdentifier("planner-apply")
    }

    private var presetGrid: some View {
        let presets = [15, 60, 120, 180, 240, 360, 480, 720, 1440, 2880, 10080]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
            ForEach(presets, id: \.self) { minutes in
                let selected = durationMinutes == minutes
                Button {
                    durationMinutes = minutes
                } label: {
                    Text(StayPlanFormatting.compactDuration(minutes))
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .adaptiveGlassControlButton(isSelected: selected)
                .accessibilityLabel(ParkingPlan.durationLabel(minutes: minutes))
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
                .accessibilityIdentifier("planner-duration-\(minutes)")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var durationSteppers: some View {
        VStack(spacing: 8) {
            stepper("Days", value: daysBinding, range: 0...7, identifier: "planner-duration-days")
            stepper("Hours", value: hoursBinding, range: 0...23, identifier: "planner-duration-hours")
            stepper("Minutes", value: minutesBinding, range: 0...59, identifier: "planner-duration-minutes")
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, identifier: String) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier(identifier)
    }

    private var daysBinding: Binding<Int> {
        Binding(
            get: { durationMinutes / (24 * 60) },
            set: { setDuration(days: $0, hours: hours, minutes: minutes) }
        )
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { (durationMinutes % (24 * 60)) / 60 },
            set: { setDuration(days: days, hours: $0, minutes: minutes) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { durationMinutes % 60 },
            set: { setDuration(days: days, hours: hours, minutes: $0) }
        )
    }

    private var days: Int { durationMinutes / (24 * 60) }
    private var hours: Int { (durationMinutes % (24 * 60)) / 60 }
    private var minutes: Int { durationMinutes % 60 }

    private func setDuration(days: Int, hours: Int, minutes: Int) {
        let total = days * 24 * 60 + hours * 60 + minutes
        durationMinutes = min(Self.maximumMinutes, max(1, total))
    }

    private var overnightSummary: String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.victoriaTimeZone
        let departure = arrival.addingTimeInterval(TimeInterval(durationMinutes * 60))
        guard !calendar.isDate(arrival, inSameDayAs: departure) else { return nil }
        let arriveText = arrival.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        let leaveText = departure.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        return "Overnight stay · arrive \(arriveText), leave \(leaveText)"
    }

    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard value.startLocation.x < 24 else { return }
                guard value.translation.width > 70, abs(value.translation.height) < 80 else { return }
                discardAndClose()
            }
    }

    private func dayButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity, minHeight: 44)
            .adaptiveGlassControlButton()
            .accessibilityIdentifier(identifier)
    }

    private func discardAndClose() {
        isPresented = false
    }

    private func applyAndClose() {
        viewModel.applyPlan(
            ParkingPlan(
                arrival: arrival,
                durationMinutes: durationMinutes,
                isPublicHoliday: isPublicHoliday
            )
        )
        isPresented = false
    }

    private static var startOfToday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = victoriaTimeZone
        return calendar.startOfDay(for: .now)
    }

    private static func rounded(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = victoriaTimeZone
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        let delta = remainder == 0 ? 0 : 5 - remainder
        return calendar.date(byAdding: .minute, value: delta, to: date) ?? date
    }

    private static func tomorrow(preserving date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = victoriaTimeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? date
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) ?? tomorrow
    }
}

struct ChromeIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var identifier: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalAccessibilityIdentifier(identifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct AboutParkingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            List {
                Section {
                    markerLegend
                }

                Section {
                    wrappingText("ParkAlong brings availability, location, active limits, and price or provider information into one parking view.")
                }

                Section("Sources") {
                    wrappingText("Only City of Melbourne currently provides verified live occupancy, from bay sensors licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).")
                    wrappingText("Council public maps and OpenStreetMap provide attributed static locations, capacities, restrictions, or prices where available.")
                    wrappingText("Posted signs and meters always govern.")
                    Link("CC BY 4.0 licence", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Link("City of Melbourne open data", destination: URL(string: "https://data.melbourne.vic.gov.au/")!)
                    Link("OpenStreetMap copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                }

                Section("Privacy") {
                    wrappingText("Your location stays on this device to centre the map. It is not stored, and this app has no account. Place search uses Apple. Live occupancy requests go only to City of Melbourne.")
                }
            }
            .navigationTitle("ParkAlong")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .adaptiveToolbarMinimizationBehavior()
    }

    private var markerLegend: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .center, spacing: 16) {
                    ForEach(AboutLegendItem.all) { item in
                        AboutMiniMarkerLegendItem(item: item)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(AboutLegendItem.all) { item in
                        AboutMiniMarkerLegendItem(item: item)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("about-legend")
    }

    private func wrappingText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AboutLegendItem: Identifiable {
    let id: String
    let label: String
    let palette: ParkingPinPalette
    let showsWarning: Bool
    let caption: String
    let accessibilityText: String

    static let all = [
        AboutLegendItem(id: "available", label: "4", palette: .liveAvailable, showsWarning: false, caption: "Available", accessibilityText: "Available, verified live"),
        AboutLegendItem(id: "limited", label: "2", palette: .liveLimited, showsWarning: false, caption: "Limited", accessibilityText: "Limited, verified live"),
        AboutLegendItem(id: "full", label: "0", palette: .liveFull, showsWarning: false, caption: "Full", accessibilityText: "Full, verified live"),
        AboutLegendItem(id: "estimate", label: "~4", palette: .predictedPlum, showsWarning: true, caption: "Estimate", accessibilityText: "Estimate, not live"),
        AboutLegendItem(id: "location", label: "P", palette: .locationRed, showsWarning: true, caption: "Location only", accessibilityText: "Location only, not live")
    ]
}

private struct AboutMiniMarkerLegendItem: View {
    let item: AboutLegendItem

    @ScaledMetric(relativeTo: .caption2) private var badgeHeight = 22.0
    @ScaledMetric(relativeTo: .caption2) private var warningSize = 8.0

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            miniMarker
                .frame(width: 44, height: 44, alignment: .center)
            Text(item.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
    }

    private var miniMarker: some View {
        let fill = item.palette.color

        return ZStack(alignment: .center) {
            VStack(spacing: 0) {
                Text(item.label)
                    .font(labelFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, item.label.count > 2 ? 4 : 6)
                    .frame(minWidth: 24, minHeight: badgeHeight)
                    .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                    }

                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(fill)
                    .offset(y: -1)
            }

            if item.showsWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: warningSize, weight: .bold))
                    .foregroundStyle(ParkingPinPalette.warningAmber)
                    .background {
                        Circle()
                            .fill(.white)
                            .padding(-1)
                    }
                    .offset(x: 12, y: -14)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44, alignment: .center)
    }

    private var labelFont: Font {
        item.palette == .locationRed
            ? .caption2.weight(.heavy)
            : .caption2.weight(.bold).monospacedDigit()
    }
}

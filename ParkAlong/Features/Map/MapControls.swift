import SwiftUI

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            statusIsland
            if viewModel.selectedOption == nil, let best = viewModel.zones.first(where: \.isBestBet) {
                BestBetButton(zone: best) {
                    Task { await viewModel.selectZone(best) }
                }
            }
            if viewModel.selectedOption == nil {
                StayDurationBar(viewModel: viewModel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("parking-action-dock")
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: viewModel.state)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: viewModel.selectedZone?.zoneNumber)
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
            if viewModel.selectedZone == nil {
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
            }
        }
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

struct BestBetButton: View {
    let zone: ParkingZone
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Best bet", systemImage: "star.fill")
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer()
                            Text("\(zone.available)")
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        Text(zone.metadata.streetName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.footnote.weight(.bold))
                            .symbolRenderingMode(.monochrome)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Best bet")
                                .font(.caption.weight(.semibold))
                            Text(zone.metadata.streetName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(zone.available)")
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
        .tint(AvailabilityStyle.color(for: zone.available))
        .accessibilityLabel("Best bet, \(zone.metadata.streetName), \(zone.available) of \(zone.total) available")
        .accessibilityIdentifier("best-bet-button")
        .sensoryFeedback(.selection, trigger: zone.zoneNumber)
    }
}

struct StayDurationBar: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var staySelection
    @State private var showingPlanner = false
    @State private var plannerPrefersEightHours = false

    private var trackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var thumbShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
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
                HStack(alignment: .center, spacing: 8) {
                    stayTrack
                    plannerButton
                    refreshButton
                }
                .adaptiveControlDock(cornerRadius: 22)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.plan)
        .sensoryFeedback(.selection, trigger: viewModel.plan.durationMinutes)
        .sheet(isPresented: $showingPlanner) {
            ArrivalStayPlannerView(viewModel: viewModel, preferEightHourDefault: plannerPrefersEightHours)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
        }
    }

    private var stayTrack: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(StayTrackItem.all.enumerated()), id: \.element.id) { index, item in
                        sizedSegment(item, index: index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if dynamicTypeSize.isAccessibilitySize {
                    proxy.scrollTo(StayTrackItem.all[0].id, anchor: .leading)
                } else {
                    proxy.scrollTo(selectedItem.id, anchor: .center)
                }
            }
            .onChange(of: selectedItem) { _, item in
                if reduceMotion {
                    proxy.scrollTo(item.id, anchor: .center)
                } else {
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .adaptiveGlassSurface(shape: trackShape, isInteractive: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stay-duration-track")
        .accessibilityAdjustableAction { direction in
            adjustStay(direction)
        }
    }

    @ViewBuilder
    private func sizedSegment(_ item: StayTrackItem, index: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            staySegment(item, index: index)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            staySegment(item, index: index)
                .containerRelativeFrame(.horizontal) { length, _ in
                    max(44, length / CGFloat(StayTrackItem.all.count))
                }
        }
    }

    private func staySegment(_ item: StayTrackItem, index: Int) -> some View {
        let selected = selectedItem == item
        return Button {
            select(item)
        } label: {
            Text(chipLabel(for: item, selected: selected))
                .font(.footnote.weight(selected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 4)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        if reduceMotion {
                            thumbShape.fill(Color.accentColor)
                        } else {
                            thumbShape
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "stay-selection", in: staySelection)
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    if showsDivider(before: index) {
                        Capsule()
                            .fill(.primary.opacity(0.16))
                            .frame(width: 1, height: 16)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityIdentifier(item.identifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func showsDivider(before index: Int) -> Bool {
        guard index > 0 else { return false }
        let items = StayTrackItem.all
        return selectedItem != items[index] && selectedItem != items[index - 1]
    }

    private var plannerButton: some View {
        Button {
            plannerPrefersEightHours = false
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
            plannerPrefersEightHours = selectedItem != .extended
            showingPlanner = true
        }
    }

    private func adjustStay(_ direction: AccessibilityAdjustmentDirection) {
        let items = StayTrackItem.presets + [.extended]
        guard let current = items.firstIndex(of: selectedItem) else { return }
        let next: Int
        switch direction {
        case .increment: next = min(items.count - 1, current + 1)
        case .decrement: next = max(0, current - 1)
        @unknown default: return
        }
        guard next != current else { return }
        select(items[next])
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
        case .extended: "8 hours or custom stay, opens arrival and stay planner"
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
    @Environment(\.dismiss) private var dismiss
    @State private var arrival: Date
    @State private var durationMinutes: Int

    private static let victoriaTimeZone = TimeZone(identifier: "Australia/Melbourne") ?? .current
    private static let maximumMinutes = 7 * 24 * 60

    init(viewModel: ParkingMapViewModel, preferEightHourDefault: Bool) {
        self.viewModel = viewModel
        let plan = viewModel.plan
        let minutes = preferEightHourDefault && plan.durationMinutes < 480 ? 480 : plan.durationMinutes
        _arrival = State(initialValue: Self.rounded(plan.arrival))
        _durationMinutes = State(initialValue: minutes)
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
                    HStack(spacing: 8) {
                        dayButton("Today", identifier: "planner-arrival-today") {
                            arrival = Self.rounded(.now)
                        }
                        dayButton("Tomorrow", identifier: "planner-arrival-tomorrow") {
                            arrival = Self.tomorrow(preserving: arrival)
                        }
                    }
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
                    Button("Close") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Reset") {
                        arrival = Self.rounded(.now)
                        durationMinutes = StayDuration.oneHour.rawValue
                        applyAndDismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("planner-reset")

                    Button("Apply") {
                        applyAndDismiss()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .adaptiveProminentAction()
                    .accessibilityIdentifier("planner-apply")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .adaptiveToolbarMinimizationBehavior()
        .environment(\.timeZone, Self.victoriaTimeZone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("arrival-stay-planner")
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

    private func dayButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity, minHeight: 44)
            .adaptiveGlassControlButton()
            .accessibilityIdentifier(identifier)
    }

    private func applyAndDismiss() {
        viewModel.applyPlan(
            ParkingPlan(
                arrival: arrival,
                durationMinutes: durationMinutes,
                isPublicHoliday: viewModel.plan.isPublicHoliday
            )
        )
        dismiss()
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

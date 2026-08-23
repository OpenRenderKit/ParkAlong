import SwiftUI

struct MapToolbarContent: ToolbarContent {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var showingAbout: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            DestinationToolbarControl(viewModel: viewModel)
        }
        .adaptiveHighVisibilityPriority()

        ToolbarItem(placement: .adaptiveTopBarPinnedTrailing) {
            Button {
                Task { await viewModel.useCurrentLocation() }
            } label: {
                Image(systemName: viewModel.destination.id == "current" ? "location.fill" : "location")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Use current location")
            .accessibilityValue(viewModel.destination.id == "current" ? "selected" : "not selected")
            .accessibilityIdentifier("current-location-button")
        }

        AdaptiveToolbarOverflowMenu {
            Button {
                showingAbout = true
            } label: {
                Label("About ParkAlong", systemImage: "info.circle")
            }
            .accessibilityLabel("About ParkAlong")
        }
    }
}

private struct DestinationToolbarControl: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
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

            ChromeIconButton(systemName: "magnifyingglass", accessibilityLabel: "Search destination", identifier: "destination-search-button") {
                viewModel.isSearching = true
            }
        }
        .frame(minWidth: 156, idealWidth: 220, maxWidth: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("destination-search-container")
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
                Text("Checking availability")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .adaptiveGlassSurface(cornerRadius: 22)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("availability-loading")
            .accessibilityLabel("Checking availability")
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

    private var statusText: String {
        if !viewModel.notice.isEmpty { return viewModel.notice }
        switch viewModel.mode {
        case .live:
            if let checkedAt = viewModel.checkedAt {
                return "Live · checked \(checkedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Live sensor availability"
        case .typical:
            return "Typical availability · live sensors unavailable"
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

    var body: some View {
        AdaptiveGlassContainer(spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    durationButtons
                    refreshButton
                }
                .padding(6)
            } else {
                HStack(spacing: 4) {
                    durationButtons
                    refreshButton
                }
                .padding(4)
            }
        }
        .adaptiveControlDock(cornerRadius: 24)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.duration)
        .sensoryFeedback(.selection, trigger: viewModel.duration)
    }

    @ViewBuilder
    private var durationButtons: some View {
        ForEach([StayDuration.fifteenMinutes, .oneHour, .twoHours, .threeHours]) { duration in
            durationButton(for: duration)
        }
        extraDurationsMenu
    }

    private func durationButton(for duration: StayDuration) -> some View {
        let selected = viewModel.duration == duration
        return Button {
            viewModel.selectDuration(duration)
        } label: {
            durationChipLabel(duration.shortLabel, selected: selected)
        }
        .adaptiveGlassControlButton(isSelected: selected)
        .accessibilityLabel(duration.accessibilityLabel)
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityIdentifier("duration-\(duration.shortLabel)")
    }

    private var extraDurationsMenu: some View {
        let extras: [StayDuration] = [.fourHours, .sixHours, .eightHours]
        let selectedExtra = extras.first { $0 == viewModel.duration }
        let selected = selectedExtra != nil

        return Menu {
            ForEach(extras) { duration in
                Button {
                    viewModel.selectDuration(duration)
                } label: {
                    Text(duration.shortLabel)
                }
                .accessibilityLabel(duration.accessibilityLabel)
                .accessibilityIdentifier("duration-\(duration.shortLabel)")
            }
        } label: {
            durationChipLabel(selectedExtra?.shortLabel ?? "More", selected: selected)
        }
        .menuIndicator(.hidden)
        .adaptiveGlassControlButton(isSelected: selected)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(selectedExtra?.accessibilityLabel ?? "More")
        .accessibilityValue(selected ? "selected" : "not selected")
        .accessibilityIdentifier("duration-more")
    }

    private func durationChipLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
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
            .frame(
                minWidth: 44,
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 44,
                minHeight: 44,
                maxHeight: 44
            )
            .contentShape(Rectangle())
        }
        .adaptiveGlassControlButton()
        .disabled({
            if case .loading = viewModel.state { return true }
            return false
        }())
        .accessibilityLabel("Refresh availability")
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 60), spacing: 10, alignment: .top)],
            spacing: 12
        ) {
            AboutMiniMarkerLegendItem(
                label: "4",
                palette: .liveAvailable,
                showsWarning: false,
                caption: "Available",
                accessibilityText: "Available, verified live"
            )
            AboutMiniMarkerLegendItem(
                label: "2",
                palette: .liveLimited,
                showsWarning: false,
                caption: "Limited",
                accessibilityText: "Limited, verified live"
            )
            AboutMiniMarkerLegendItem(
                label: "0",
                palette: .liveFull,
                showsWarning: false,
                caption: "Full",
                accessibilityText: "Full, verified live"
            )
            AboutMiniMarkerLegendItem(
                label: "~4",
                palette: .predictedPlum,
                showsWarning: true,
                caption: "Estimate",
                accessibilityText: "Estimate, not live"
            )
            AboutMiniMarkerLegendItem(
                label: "P",
                palette: .locationRed,
                showsWarning: true,
                caption: "Location only",
                accessibilityText: "Location only, not live"
            )
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        .accessibilityElement(children: .contain)
    }

    private func wrappingText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AboutMiniMarkerLegendItem: View {
    let label: String
    let palette: ParkingPinPalette
    let showsWarning: Bool
    let caption: String
    let accessibilityText: String

    @ScaledMetric(relativeTo: .caption2) private var badgeHeight = 22.0
    @ScaledMetric(relativeTo: .caption2) private var warningSize = 8.0

    var body: some View {
        VStack(spacing: 6) {
            miniMarker
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var miniMarker: some View {
        let fill = palette.color

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, label.count > 2 ? 4 : 6)
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
            .padding(.top, showsWarning ? 4 : 0)
            .padding(.trailing, showsWarning ? 4 : 0)

            if showsWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: warningSize, weight: .bold))
                    .foregroundStyle(ParkingPinPalette.warningAmber)
                    .background {
                        Circle()
                            .fill(.white)
                            .padding(-1)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var labelFont: Font {
        palette == .locationRed
            ? .caption2.weight(.heavy)
            : .caption2.weight(.bold).monospacedDigit()
    }
}

import SwiftUI

struct MapSearchBar: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Binding var showingAbout: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.destination.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier("destination-title")

                if !viewModel.destination.subtitle.isEmpty {
                    Text(viewModel.destination.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChromeIconButton(systemName: "magnifyingglass", accessibilityLabel: "Search destination", identifier: "destination-search-button") {
                viewModel.isSearching = true
            }

            ChromeIconButton(
                systemName: viewModel.destination.id == "current" ? "location.fill" : "location",
                accessibilityLabel: "Use current location"
            ) {
                Task { await viewModel.useCurrentLocation() }
            }

            ChromeIconButton(systemName: "info.circle", accessibilityLabel: "About ParkAlong") {
                showingAbout = true
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
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
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(minHeight: 44)
                .accessibilityIdentifier("retry-button")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        case .loaded:
            if viewModel.selectedZone == nil {
                Text(statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
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

    var body: some View {
        Button(action: action) {
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
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(AvailabilityStyle.color(for: zone.available), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        durationButtons
                    }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: viewModel.duration)
        .sensoryFeedback(.selection, trigger: viewModel.duration)
    }

    @ViewBuilder
    private var durationButtons: some View {
        ForEach(StayDuration.allCases) { duration in
            let selected = viewModel.duration == duration
            Button {
                Task { await viewModel.updateDuration(duration) }
            } label: {
                Text(duration.shortLabel)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.primary)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(duration.accessibilityLabel)
            .accessibilityValue(selected ? "selected" : "not selected")
            .accessibilityIdentifier("duration-\(duration.shortLabel)")
        }
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
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    Text("ParkAlong brings availability, location, active limits, and price or provider information into one parking view.")
                }

                Section("Source") {
                    Text("On-street bay occupancy comes from City of Melbourne sensor data, licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).")
                    Link("CC BY 4.0 licence", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Link("City of Melbourne open data", destination: URL(string: "https://data.melbourne.vic.gov.au/")!)
                }

                Section("Privacy") {
                    Text("Your location stays on this device to centre the map. It is not stored, and this app has no account. Place search uses Apple. Sensor requests go to City of Melbourne.")
                }

                Section("Caveats") {
                    Text("Counts are indicative and change quickly. Posted signs and meters always govern. Sensors can misread on public holidays and in construction zones. Typical figures are historical patterns used only when live data is missing or stale.")
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
    }
}

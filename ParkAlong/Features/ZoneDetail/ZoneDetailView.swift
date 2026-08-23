import SwiftUI

struct ZoneDetailView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let option = viewModel.selectedOption {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if option.classification != .verifiedLive {
                            warningCard(warningCopy(option))
                        }
                        title(option)
                        facts(option)
                        secondary(option)
                        source(option)
                        disclaimers(option)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .safeAreaInset(edge: .bottom) { navigation }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zone-detail-sheet")
    }

    private func warningCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(ParkingPinPalette.warningAmber)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("data-quality-warning")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ParkingPinPalette.warningAmber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ParkingPinPalette.warningAmber.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func title(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(option.kind.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if option.isBestBet {
                    Text("BEST BET")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AvailabilityStyle.color(for: option.available ?? 0))
                }
            }
            Text(option.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Label(option.locationLabel, systemImage: "location.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func facts(_ option: ParkingOption) -> some View {
        VStack(spacing: 0) {
            factRow(
                option.classification == .predicted ? "ESTIMATE" : "AVAILABILITY",
                option.availabilityLabel,
                color: availabilityColor(option),
                identifier: "zone-availability"
            )
            Divider()
            factRow("TIME LIMIT", option.restrictionLabel, color: .primary, identifier: "zone-time-limit")
            caption(option.restrictionWindow)
            Divider()
            factRow(
                "PRICE",
                option.price.primaryText,
                color: option.price.primaryText == "Free" ? .green : .primary,
                identifier: "zone-price",
                accessibilityLabel: priceLabel(option.price)
            )
            caption(option.price.detail)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func factRow(_ title: String, _ value: String, color: Color, identifier: String, accessibilityLabel: String? = nil) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    valueText(value, color: color, identifier: identifier, accessibilityLabel: accessibilityLabel)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    valueText(value, color: color, identifier: identifier, accessibilityLabel: accessibilityLabel)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func valueText(_ value: String, color: Color, identifier: String, accessibilityLabel: String?) -> some View {
        Text(value)
            .font(.title3.weight(.bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(accessibilityLabel ?? value)
    }

    @ViewBuilder
    private func caption(_ text: String) -> some View {
        if text.isEmpty {
            Color.clear.frame(height: 6)
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func secondary(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(walk(option.walkingMetres), systemImage: "figure.walk")
            if let prediction = option.prediction {
                Label(prediction.simpleLabel, systemImage: "chart.bar.fill")
                    .foregroundStyle(.secondary)
                Text("Confidence \(Int((prediction.confidence * 100).rounded()))% · \(prediction.chanceLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func source(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(option.provider)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if option.classification == .verifiedLive, let timestamp = option.sourceTimestamp {
                Text("Sensor updated \(timestamp.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let dataset = option.sourceDatasetAt {
                Text("Dataset date \(dataset.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let checked = option.sourceCheckedAt {
                Text("ParkAlong checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = option.price.actionURL {
                Link(destination: url) {
                    Label(option.price.actionLabel ?? "View official source", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func disclaimers(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Posted signs govern.")
                .font(.subheadline.weight(.semibold))
            Text(option.kind == .onStreet
                 ? "Counts and estimates can change. Check the sign and meter before you leave the car. Sensors can misread on public holidays and near construction."
                 : "Facility hours, spaces and prices are controlled by the provider. Check before you travel.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var navigation: some View {
        VStack(spacing: 8) {
            Button { viewModel.navigate() } label: {
                Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .adaptiveProminentAction()
            .controlSize(.large)
            .accessibilityIdentifier("navigate-button")
            if viewModel.navigationWasIntercepted {
                Text("Navigation handoff ready")
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("navigation-intercepted")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func warningCopy(_ option: ParkingOption) -> String {
        let text = option.warningText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.localizedCaseInsensitiveContains("not live") {
            return text
        }
        return text.isEmpty ? "Not live" : "\(text) · not live"
    }

    private func availabilityColor(_ option: ParkingOption) -> Color {
        switch option.classification {
        case .verifiedLive:
            AvailabilityStyle.color(for: option.available ?? 0)
        case .predicted:
            ParkingPinPalette.predictedPlumColor
        case .staticOnly, .staleHistorical:
            .primary
        }
    }

    private func priceLabel(_ price: ParkingPriceInformation) -> String {
        price.detail.isEmpty ? price.primaryText : "\(price.primaryText). \(price.detail)"
    }

    private func walk(_ metres: Double) -> String {
        metres < 1_000 ? "\(Int(metres.rounded())) m walk" : String(format: "%.1f km walk", metres / 1_000)
    }
}

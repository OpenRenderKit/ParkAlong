import SwiftUI

struct ZoneDetailView: View {
    @Bindable var viewModel: ParkingMapViewModel

    var body: some View {
        Group {
            if let option = viewModel.selectedOption {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        title(option)
                        primaryFacts(option)
                        provider(option)
                        secondary(option)
                        disclaimers(option)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                }
                .safeAreaInset(edge: .bottom) { navigation }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zone-detail-sheet")
    }

    private func title(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(option.kind.rawValue.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                if option.isBestBet { Text("BEST BET").font(.caption2.weight(.bold)).foregroundStyle(.green) }
            }
            Text(option.title).font(.title2.weight(.bold))
            Label(option.locationLabel, systemImage: "location.fill")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryFacts(_ option: ParkingOption) -> some View {
        VStack(spacing: 0) {
            heroFact("AVAILABLE", option.availabilityLabel, color: availabilityColor(option))
                .accessibilityIdentifier("zone-availability")
            Divider()
            heroFact("TIME LIMIT", option.restrictionLabel, color: .primary)
                .accessibilityIdentifier("zone-time-limit")
            Text(option.restrictionWindow).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            heroFact("PRICE", option.price.primaryText, color: option.price.primaryText == "Free" ? .green : .primary)
            Text(option.price.detail).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)) }
    }

    private func heroFact(_ label: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 88, alignment: .leading)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).accessibilityElement(children: .combine)
    }

    @ViewBuilder private func provider(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PROVIDER / PAYMENT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(option.provider).font(.headline)
            if let url = option.price.actionURL, let label = option.price.actionLabel {
                Link(destination: url) { Label(label, systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private func secondary(_ option: ParkingOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(walk(option.walkingMetres), systemImage: "figure.walk")
            if let prediction = option.prediction {
                Label("Likely still free on arrival · \(prediction.chanceLabel)", systemImage: "clock.badge.checkmark")
                    .foregroundStyle(.secondary)
            }
            if let timestamp = option.sourceTimestamp {
                Text("Sensor updated \(timestamp.formatted(.relative(presentation: .named)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.font(.subheadline)
    }

    private func disclaimers(_ option: ParkingOption) -> some View {
        Text(option.kind == .onStreet
             ? "Availability changes. Street signs govern. Sensors can be unreliable on public holidays and near construction."
             : "Facility availability, hours and prices are controlled by the provider. Check before travelling.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var navigation: some View {
        VStack(spacing: 8) {
            Button { viewModel.navigate() } label: {
                Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("navigate-button")
            if viewModel.navigationWasIntercepted {
                Text("Navigation handoff ready").font(.footnote.weight(.semibold)).accessibilityIdentifier("navigation-intercepted")
            }
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }

    private func availabilityColor(_ option: ParkingOption) -> Color {
        guard let count = option.available else { return .indigo }
        return AvailabilityStyle.color(for: count)
    }

    private func walk(_ metres: Double) -> String {
        metres < 1_000 ? "\(Int(metres.rounded())) m walk" : String(format: "%.1f km walk", metres / 1_000)
    }
}

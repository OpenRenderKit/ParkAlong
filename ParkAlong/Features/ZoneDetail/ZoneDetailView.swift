import SwiftUI

struct ZoneDetailView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingScheduleExplorer = false

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
                        ForecastEvidenceView(option: option, plan: viewModel.plan)
                        secondary(option)
                        source(option)
                        disclaimers(option)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .safeAreaInset(edge: .bottom) { navigation }
                .sheet(isPresented: $showingScheduleExplorer) {
                    ScheduleExplorerView(option: option, plan: viewModel.plan)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.resizes)
                }
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
            Button {
                showingScheduleExplorer = true
            } label: {
                VStack(spacing: 0) {
                    factRow("TIME LIMIT", option.restrictionLabel, color: .primary, identifier: "zone-time-limit")
                    caption(option.restrictionWindow)
                    HStack {
                        Text("Weekly schedule")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("zone-time-limit-row")
            .accessibilityHint("Shows the weekly parking schedule")
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
        Label(walk(option.walkingMetres), systemImage: "figure.walk")
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

struct ForecastEvidenceView: View {
    let option: ParkingOption
    let plan: ParkingPlan

    var body: some View {
        if let prediction = option.prediction {
            VStack(alignment: .leading, spacing: 8) {
                Label(headline(prediction), systemImage: icon(prediction))
                    .font(.subheadline.weight(.semibold))
                Text(detail(prediction))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowProbability(prediction), let probability = prediction.probabilityAtLeastOne {
                    Text("Modelled chance of at least one space: \(percent(probability))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("forecast-probability")
                    Text(prediction.chanceLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let validation = prediction.validation {
                    DisclosureGroup("Forecast model details") {
                        VStack(alignment: .leading, spacing: 6) {
                            if let version = prediction.modelVersion, !version.isEmpty {
                                labeled("Model", version)
                            }
                            labeled("Validation samples", "\(validation.sampleCount)")
                            labeled("Interval coverage", percent(validation.intervalCoverage))
                            labeled("Brier score", String(format: "%.3f", validation.brierScore))
                            labeled("Held-out interval radius", conformalRadiusCopy(validation.intervalRadius))
                                .accessibilityIdentifier("forecast-interval-radius")
                            Text("Measured width of the forecast interval on held-out tests. This is not a live certainty score.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("The any-space chance is derived from held-out scored per-bay vacancy rates and assumes bays behave independently. It is a model estimate, not a certainty or a directly measured segment outcome.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            labeled("Observed through", validation.observedThrough.formatted(date: .abbreviated, time: .omitted))
                            labeled("Horizon", "\(prediction.horizonMinutes) min")
                        }
                        .padding(.top, 4)
                    }
                    .accessibilityIdentifier("forecast-model-details")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("forecast-evidence")
        }
    }

    private func headline(_ prediction: AvailabilityPrediction) -> String {
        switch prediction.evidenceTier {
        case .liveObserved:
            "Live observation"
        case .liveInformed:
            prediction.hasNumericForecast ? prediction.simpleLabel : "Live-informed forecast"
        case .historical:
            prediction.hasNumericForecast ? prediction.simpleLabel : "Historical forecast"
        case .demandOutlook:
            "Demand outlook"
        case .abstained:
            "Forecast unavailable"
        }
    }

    private func icon(_ prediction: AvailabilityPrediction) -> String {
        switch prediction.evidenceTier {
        case .liveObserved: "antenna.radiowaves.left.and.right"
        case .liveInformed, .historical: "chart.bar.fill"
        case .demandOutlook: "chart.line.uptrend.xyaxis"
        case .abstained: "questionmark.circle"
        }
    }

    private func detail(_ prediction: AvailabilityPrediction) -> String {
        switch prediction.evidenceTier {
        case .liveObserved:
            if let available = option.available, let total = option.total {
                let age = option.sourceTimestamp.map { "Observed \($0.formatted(.relative(presentation: .named)))." } ?? ""
                return "\(available) of \(total) spaces observed live. \(age)".trimmingCharacters(in: .whitespaces)
            }
            return "A live occupancy observation is available for this arrival."
        case .liveInformed, .historical:
            if prediction.hasNumericForecast {
                let arrival = StayPlanFormatting.arrivalCaption(for: plan) ?? "the planned arrival"
                return "Likely range for \(arrival.lowercased()). This is a measured forecast, not a live count."
            }
            return "A numeric vacancy forecast is not available for this arrival."
        case .demandOutlook:
            return "This is a demand outlook only. A vacancy count is not available."
        case .abstained:
            return abstentionCopy(prediction.abstentionReason)
        }
    }

    private func shouldShowProbability(_ prediction: AvailabilityPrediction) -> Bool {
        prediction.evidenceTier != .liveObserved && prediction.hasNumericForecast
    }

    private func abstentionCopy(_ reason: ForecastAbstentionReason?) -> String {
        switch reason {
        case .missingCapacity:
            "No reliable forecast: capacity is unknown."
        case .missingHistory:
            "No reliable forecast: there is not enough observation history."
        case .missingValidation:
            "No reliable forecast: this model has not been validated for this place."
        case .insufficientSupport:
            "No reliable forecast: there is not enough supporting evidence."
        case .poorCalibration:
            "No reliable forecast: the model is not well calibrated here."
        case .staleModel:
            "No reliable forecast: the model is out of date."
        case .distributionShift:
            "No reliable forecast: conditions differ from the data used to train the model."
        case nil:
            "No reliable forecast for the planned arrival."
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }

    private func conformalRadiusCopy(_ radius: Double) -> String {
        "±\(percent(radius)) of spaces"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct ScheduleExplorerView: View {
    let option: ParkingOption
    let plan: ParkingPlan
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDayID: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    arrivalContext
                    dayStrip
                    blocksList
                }
                .padding(20)
            }
            .navigationTitle("Time limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
        }
        .adaptiveToolbarMinimizationBehavior()
        .onAppear {
            selectedDayID = matchingDay?.id ?? option.schedule.first?.id
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule-explorer")
    }

    private var selectedDay: ParkingScheduleDay? {
        option.schedule.first { $0.id == selectedDayID } ?? matchingDay ?? option.schedule.first
    }

    private var matchingDay: ParkingScheduleDay? {
        option.schedule.first { victoriaCalendar.isDate($0.date, inSameDayAs: plan.arrival) }
    }

    private var victoriaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne") ?? .current
        return calendar
    }

    private var arrivalContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(option.restrictionLabel)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(option.restrictionWindow)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Showing rules for arrival \(plan.arrival.formatted(.dateTime.weekday(.wide).hour().minute())) · \(plan.durationLabel) stay")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("schedule-arrival-context")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var dayStrip: some View {
        if option.schedule.isEmpty {
            ContentUnavailableView(
                "No weekly schedule",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("A day-by-day restriction schedule is not available for this location.")
            )
            .accessibilityIdentifier("schedule-empty")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(option.schedule.enumerated()), id: \.element.id) { index, day in
                        let selected = day.id == selectedDay?.id
                        Button {
                            selectedDayID = day.id
                        } label: {
                            VStack(spacing: 2) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption.weight(.semibold))
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.headline.monospacedDigit())
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, 8)
                        }
                        .adaptiveGlassControlButton(isSelected: selected)
                        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("schedule-day-\(index)")
                    }
                }
            }
            .accessibilityIdentifier("schedule-day-strip")
        }
    }

    @ViewBuilder
    private var blocksList: some View {
        if let selectedDay {
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedDay.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline.weight(.semibold))
                ForEach(selectedDay.blocks) { block in
                    scheduleBlockRow(block, on: selectedDay)
                }
            }
        }
    }

    private func scheduleBlockRow(_ block: ParkingScheduleBlock, on day: ParkingScheduleDay) -> some View {
        let highlighted = containsArrival(block, on: day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(timeLabel(block.startMinutes)) – \(timeLabel(block.endMinutes))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer(minLength: 8)
                Text(stateLabel(block))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stateColor(block).opacity(0.18), in: Capsule())
                    .foregroundStyle(stateColor(block))
            }
            Text(block.title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = block.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if highlighted {
                Text("Contains the selected arrival")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("schedule-selected-arrival-block")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: highlighted ? 1.5 : 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule-block-\(block.id)")
    }

    private func containsArrival(_ block: ParkingScheduleBlock, on day: ParkingScheduleDay) -> Bool {
        guard victoriaCalendar.isDate(day.date, inSameDayAs: plan.arrival) else { return false }
        let minute = victoriaCalendar.component(.hour, from: plan.arrival) * 60 + victoriaCalendar.component(.minute, from: plan.arrival)
        return block.startMinutes <= minute && minute < block.endMinutes
    }

    private func timeLabel(_ minutes: Int) -> String {
        if minutes >= 24 * 60 { return "Midnight" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne") ?? .current
        let start = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        return date.formatted(.dateTime.hour().minute())
    }

    private func stateLabel(_ block: ParkingScheduleBlock) -> String {
        switch block.kind {
        case .unrestricted:
            return "Unrestricted"
        case .unknown:
            return "Unknown"
        case .restricted:
            if block.isPaid == true { return "Paid" }
            if block.isPaid == false { return "Free" }
            return "Restricted"
        }
    }

    private func stateColor(_ block: ParkingScheduleBlock) -> Color {
        switch block.kind {
        case .unrestricted:
            return Color.green
        case .unknown:
            return Color.secondary
        case .restricted:
            if block.isPaid == true { return Color.orange }
            if block.isPaid == false { return Color.green }
            return Color.primary
        }
    }
}

import Foundation

struct ResolvedParkingRule: Equatable, Sendable {
    let timeLimitText: String
    let restrictionWindow: String
    let price: ParkingPriceInformation
    let isEligible: Bool
    let classification: ParkingDataClassification
}

struct ParkingTimeFormatter: Sendable {
    let timeZone: TimeZone

    func string(minutes: Int) -> String {
        let normalized = minutes == 24 * 60 ? 0 : minutes
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = normalized / 60
        components.minute = normalized % 60

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"

        return formatter.string(from: components.date ?? .distantPast)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
    }
}

struct ParkingRuleResolver: Sendable {
    let timeZone: TimeZone

    init(timeZone: TimeZone = TimeZone(identifier: "Australia/Melbourne")!) {
        self.timeZone = timeZone
    }

    func resolve(
        location: StaticParkingLocation,
        at date: Date,
        duration: StayDuration,
        isPublicHoliday: Bool = false
    ) -> ResolvedParkingRule? {
        let activeSchedules = location.schedules.filter {
            scheduleIsActive($0, at: date, isPublicHoliday: isPublicHoliday)
        }

        guard !activeSchedules.isEmpty else {
            let isKnownFreeWindow = !location.schedules.isEmpty
                && location.schedules.contains(where: \.outsideWindowMeansUnrestricted)
            return ResolvedParkingRule(
                timeLimitText: isKnownFreeWindow ? "No timed limit right now" : "Check posted signs",
                restrictionWindow: isKnownFreeWindow ? "Outside signed control hours" : "Current restriction is not machine-readable",
                price: isKnownFreeWindow ? freeNowPrice(source: location.source) : unknownPrice(source: location.source),
                isEligible: true,
                classification: location.classification
            )
        }

        let schedule = activeSchedules.min {
            ($0.maxStayMinutes ?? .max) < ($1.maxStayMinutes ?? .max)
        }!
        let eligible = schedule.maxStayMinutes.map { $0 >= duration.rawValue } ?? true
        let end = formattedTime(minutes: schedule.endMinutes)
        let limit = schedule.maxStayMinutes.map(Self.limitLabel) ?? schedule.restrictionText
        let price = resolvedPrice(
            tariffs: location.tariffs,
            at: date,
            duration: duration,
            source: location.source
        )

        return ResolvedParkingRule(
            timeLimitText: "\(limit) until \(end)",
            restrictionWindow: "Active now · ends \(end)",
            price: price,
            isEligible: eligible,
            classification: location.classification
        )
    }

    private func resolvedPrice(
        tariffs: [ParkingTariff],
        at date: Date,
        duration: StayDuration,
        source: ParkingSourceAttribution
    ) -> ParkingPriceInformation {
        guard let tariff = tariffs.first(where: { tariffIsActive($0, at: date) }) else {
            let hasCurrentTariff = tariffs.contains {
                date >= $0.effectiveFrom && ($0.effectiveTo.map { date <= $0 } ?? true)
            }
            return hasCurrentTariff ? freeNowPrice(source: source) : unknownPrice(source: source)
        }

        let requestedMinutes = duration.rawValue
        let priceCents: Int?
        if let tier = tariff.tiers.sorted(by: { $0.upToMinutes < $1.upToMinutes })
            .first(where: { requestedMinutes <= $0.upToMinutes }) {
            priceCents = tier.priceCents
        } else if tariff.freeMinutes > 0 && requestedMinutes <= tariff.freeMinutes {
            priceCents = 0
        } else if let hourly = tariff.hourlyCents {
            let paidMinutes = max(0, requestedMinutes - tariff.freeMinutes)
            priceCents = Int(ceil(Double(paidMinutes) / 60.0)) * hourly
        } else {
            priceCents = tariff.dailyCapCents
        }

        guard let rawPrice = priceCents else { return unknownPrice(source: source) }
        let cappedPrice = tariff.dailyCapCents.map { min(rawPrice, $0) } ?? rawPrice
        let primary = cappedPrice == 0
            ? "Free for \(durationLabel(requestedMinutes))"
            : "\(money(cappedPrice)) for \(durationLabel(requestedMinutes))"

        let detail: String
        if let hourly = tariff.hourlyCents {
            var pieces: [String] = []
            if tariff.freeMinutes > 0 {
                let freePeriod = tariff.freeMinutes == 60 ? "hour" : durationLabel(tariff.freeMinutes)
                pieces.append("First \(freePeriod) free")
            }
            pieces.append("\(tariff.freeMinutes > 0 ? "then " : "")\(money(hourly))/hr")
            if let cap = tariff.dailyCapCents { pieces.append("\(money(cap)) daily cap") }
            detail = pieces.joined(separator: " · ")
        } else if let cap = tariff.dailyCapCents {
            detail = tariff.freeMinutes > 0
                ? "First \(durationLabel(tariff.freeMinutes)) free · then up to \(money(cap)) daily"
                : "Up to \(money(cap)) daily"
        } else {
            detail = "Official tariff checked \(source.checkedAt.formatted(date: .abbreviated, time: .omitted))"
        }

        return ParkingPriceInformation(
            primaryText: primary,
            detail: detail,
            provider: source.name,
            actionLabel: "View official parking information",
            actionURL: source.sourceURL
        )
    }

    private func scheduleIsActive(_ schedule: ParkingSchedule, at date: Date, isPublicHoliday: Bool) -> Bool {
        if isPublicHoliday && !schedule.appliesOnPublicHolidays { return false }
        let (weekday, minute) = localComponents(for: date)
        return windowMatches(days: schedule.days, start: schedule.startMinutes, end: schedule.endMinutes, weekday: weekday, minute: minute)
    }

    private func tariffIsActive(_ tariff: ParkingTariff, at date: Date) -> Bool {
        guard date >= tariff.effectiveFrom, tariff.effectiveTo.map({ date <= $0 }) ?? true else { return false }
        let (weekday, minute) = localComponents(for: date)
        return windowMatches(days: tariff.days, start: tariff.startMinutes, end: tariff.endMinutes, weekday: weekday, minute: minute)
    }

    private func localComponents(for date: Date) -> (weekday: Int, minute: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return (values.weekday ?? 1, (values.hour ?? 0) * 60 + (values.minute ?? 0))
    }

    private func windowMatches(days: [Int], start: Int, end: Int, weekday: Int, minute: Int) -> Bool {
        if start == 0 && end >= 24 * 60 { return days.contains(weekday) }
        if start < end { return days.contains(weekday) && minute >= start && minute < end }
        if minute >= start { return days.contains(weekday) }
        let previous = weekday == 1 ? 7 : weekday - 1
        return minute < end && days.contains(previous)
    }

    private func formattedTime(minutes: Int) -> String {
        ParkingTimeFormatter(timeZone: timeZone).string(minutes: minutes)
    }

    private static func limitLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours.rounded() == hours ? "\(Int(hours))P" : "\(minutes) min"
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        if hours.rounded() == hours {
            let value = Int(hours)
            return "\(value) hour\(value == 1 ? "" : "s")"
        }
        return "\(minutes) min"
    }

    private func money(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    private func freeNowPrice(source: ParkingSourceAttribution) -> ParkingPriceInformation {
        .init(primaryText: "Free right now", detail: "Outside verified payment hours", provider: source.name,
              actionLabel: "View official parking information", actionURL: source.sourceURL)
    }

    private func unknownPrice(source: ParkingSourceAttribution) -> ParkingPriceInformation {
        .init(primaryText: "Price not verified", detail: "Check the meter or facility notice", provider: source.name,
              actionLabel: "View official parking information", actionURL: source.sourceURL)
    }
}

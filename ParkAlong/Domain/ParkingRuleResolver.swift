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

    func resolve(location: StaticParkingLocation, plan: ParkingPlan) -> ResolvedParkingRule? {
        let activeSchedules = location.schedules.filter {
            scheduleIsActive($0, at: plan.arrival, isPublicHoliday: plan.isPublicHoliday)
        }
        let isEligible = planIsEligible(schedules: location.schedules, plan: plan)

        if activeSchedules.contains(where: { $0.unparsedCondition != nil }) {
            return ResolvedParkingRule(
                timeLimitText: "Check posted signs",
                restrictionWindow: "A mapped condition could not be interpreted safely",
                price: unknownPrice(source: location.source), isEligible: false,
                classification: location.classification
            )
        }

        guard !activeSchedules.isEmpty else {
            let isKnownFreeWindow = !location.schedules.isEmpty
                && location.schedules.contains(where: \.outsideWindowMeansUnrestricted)
            return ResolvedParkingRule(
                timeLimitText: isKnownFreeWindow ? "No timed limit right now" : "Check posted signs",
                restrictionWindow: isKnownFreeWindow ? "Outside signed control hours" : "Current restriction is not machine-readable",
                price: isKnownFreeWindow ? freeNowPrice(source: location.source) : unknownPrice(source: location.source),
                isEligible: isEligible,
                classification: location.classification
            )
        }

        let schedule = activeSchedules.min {
            ($0.maxStayMinutes ?? .max) < ($1.maxStayMinutes ?? .max)
        }!
        let end = formattedTime(minutes: schedule.endMinutes)
        let limit = schedule.maxStayMinutes.map(Self.limitLabel) ?? schedule.restrictionText
        let price = resolvedPrice(
            tariffs: location.tariffs,
            plan: plan,
            source: location.source
        )

        return ResolvedParkingRule(
            timeLimitText: "\(limit) until \(end)",
            restrictionWindow: "Active now · ends \(end)",
            price: price,
            isEligible: isEligible,
            classification: location.classification
        )
    }

    func weeklySchedule(location: StaticParkingLocation, plan: ParkingPlan) -> [ParkingScheduleDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: plan.arrival)
        return (0..<7).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let weekday = calendar.component(.weekday, from: day)
            let intervals = scheduleIntervals(
                schedules: location.schedules, day: day, nextDay: nextDay,
                isPublicHoliday: dayOffset == 0 && plan.isPublicHoliday
            )
            let boundaries = Set([day, nextDay] + intervals.flatMap { [$0.start, $0.end] }).sorted()
            let blocks = zip(boundaries, boundaries.dropFirst()).enumerated().compactMap { index, pair -> ParkingScheduleBlock? in
                guard pair.0 < pair.1 else { return nil }
                let midpoint = pair.0.addingTimeInterval(pair.1.timeIntervalSince(pair.0) / 2)
                let active = intervals.filter { $0.start <= midpoint && midpoint < $0.end }.map(\.schedule)
                let startMinutes = max(0, Int(pair.0.timeIntervalSince(day) / 60))
                let endMinutes = min(24 * 60, Int(pair.1.timeIntervalSince(day) / 60))
                let activeTariff = location.tariffs.first { tariffIsActive($0, at: midpoint) }
                let hasKnownTariffs = location.tariffs.contains { tariffIsEffective($0, at: midpoint) }
                if let tightest = active.min(by: { ($0.maxStayMinutes ?? .max) < ($1.maxStayMinutes ?? .max) }) {
                    if tightest.unparsedCondition != nil {
                        return ParkingScheduleBlock(
                            id: "\(weekday)-\(index)-unknown", startMinutes: startMinutes, endMinutes: endMinutes,
                            kind: .unknown, title: "Check posted signs", detail: tightest.unparsedCondition,
                            maxStayMinutes: nil, isPaid: nil
                        )
                    }
                    return ParkingScheduleBlock(
                        id: "\(weekday)-\(index)-restricted", startMinutes: startMinutes, endMinutes: endMinutes,
                        kind: .restricted, title: tightest.maxStayMinutes.map(Self.limitLabel) ?? tightest.restrictionText,
                        detail: tightest.restrictionText, maxStayMinutes: tightest.maxStayMinutes,
                        isPaid: activeTariff == nil ? (hasKnownTariffs ? false : nil) : true
                    )
                }
                let unrestricted = location.schedules.contains(where: \.outsideWindowMeansUnrestricted)
                return ParkingScheduleBlock(
                    id: "\(weekday)-\(index)-\(unrestricted ? "free" : "unknown")",
                    startMinutes: startMinutes, endMinutes: endMinutes,
                    kind: unrestricted ? .unrestricted : .unknown,
                    title: unrestricted ? "Unrestricted" : "Check posted signs",
                    detail: unrestricted ? "Outside mapped control hours" : "No machine-readable rule for this period",
                    maxStayMinutes: nil, isPaid: unrestricted ? false : nil
                )
            }
            return ParkingScheduleDay(date: day, weekday: weekday, blocks: blocks)
        }
    }

    private func resolvedPrice(
        tariffs: [ParkingTariff],
        plan: ParkingPlan,
        source: ParkingSourceAttribution
    ) -> ParkingPriceInformation {
        let priced = tariffs.compactMap { tariff -> (ParkingTariff, Int)? in
            let minutes = tariffControlledMinutes(tariff, plan: plan)
            return minutes > 0 ? (tariff, minutes) : nil
        }
        guard !priced.isEmpty else {
            let hasCurrentTariff = tariffs.contains { tariffIsEffective($0, at: plan.arrival) }
            return hasCurrentTariff ? freeNowPrice(source: source) : unknownPrice(source: source)
        }

        let components = priced.compactMap { tariff, minutes -> Int? in priceCents(tariff: tariff, controlledMinutes: minutes) }
        guard components.count == priced.count else { return unknownPrice(source: source) }
        let totalPrice = components.reduce(0, +)
        let primary = totalPrice == 0
            ? "Free for \(plan.durationLabel)"
            : "\(money(totalPrice)) for \(plan.durationLabel)"

        let tariff = priced[0].0
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

    private func priceCents(tariff: ParkingTariff, controlledMinutes: Int) -> Int? {
        let raw: Int?
        if let tier = tariff.tiers.sorted(by: { $0.upToMinutes < $1.upToMinutes })
            .first(where: { controlledMinutes <= $0.upToMinutes }) {
            raw = tier.priceCents
        } else if tariff.freeMinutes > 0 && controlledMinutes <= tariff.freeMinutes {
            raw = 0
        } else if let hourly = tariff.hourlyCents {
            let paidMinutes = max(0, controlledMinutes - tariff.freeMinutes)
            raw = Int(ceil(Double(paidMinutes) / 60.0)) * hourly
        } else {
            raw = tariff.dailyCapCents
        }
        guard let raw else { return nil }
        return tariff.dailyCapCents.map { min(raw, $0) } ?? raw
    }

    private func tariffControlledMinutes(_ tariff: ParkingTariff, plan: ParkingPlan) -> Int {
        scheduleIntervals(days: tariff.days, startMinutes: tariff.startMinutes, endMinutes: tariff.endMinutes,
                          from: plan.arrival, through: plan.departure)
            .reduce(0) { total, interval in
                let start = max(interval.start, plan.arrival, tariff.effectiveFrom)
                let effectiveEnd = tariff.effectiveTo ?? .distantFuture
                let end = min(interval.end, plan.departure, effectiveEnd)
                return total + max(0, Int(ceil(end.timeIntervalSince(start) / 60)))
            }
    }

    private func planIsEligible(schedules: [ParkingSchedule], plan: ParkingPlan) -> Bool {
        for schedule in schedules {
            for interval in scheduleIntervals(schedule: schedule, from: plan.arrival, through: plan.departure) {
                let seconds = controlledSeconds(interval: interval, schedule: schedule, plan: plan)
                if schedule.unparsedCondition != nil && seconds > 0 { return false }
                if let maximum = schedule.maxStayMinutes, seconds > TimeInterval(maximum * 60) { return false }
            }
        }
        return true
    }

    private func controlledSeconds(interval: ScheduleInterval, schedule: ParkingSchedule, plan: ParkingPlan) -> TimeInterval {
        let start = max(interval.start, plan.arrival)
        let end = min(interval.end, plan.departure)
        var seconds = max(0, end.timeIntervalSince(start))
        guard plan.isPublicHoliday, !schedule.appliesOnPublicHolidays else { return seconds }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let holidayStart = calendar.startOfDay(for: plan.arrival)
        let holidayEnd = calendar.date(byAdding: .day, value: 1, to: holidayStart)!
        let excludedStart = max(start, holidayStart)
        let excludedEnd = min(end, holidayEnd)
        seconds -= max(0, excludedEnd.timeIntervalSince(excludedStart))
        return max(0, seconds)
    }

    private struct ScheduleInterval {
        let schedule: ParkingSchedule
        let start: Date
        let end: Date
    }

    private func scheduleIntervals(
        schedules: [ParkingSchedule], day: Date, nextDay: Date, isPublicHoliday: Bool
    ) -> [ScheduleInterval] {
        schedules.filter { !isPublicHoliday || $0.appliesOnPublicHolidays }.flatMap { schedule in
            scheduleIntervals(schedule: schedule, from: day, through: nextDay).compactMap { interval in
                let start = max(day, interval.start)
                let end = min(nextDay, interval.end)
                return start < end ? ScheduleInterval(schedule: schedule, start: start, end: end) : nil
            }
        }
    }

    private func scheduleIntervals(schedule: ParkingSchedule, from start: Date, through end: Date) -> [ScheduleInterval] {
        scheduleIntervals(days: schedule.days, startMinutes: schedule.startMinutes, endMinutes: schedule.endMinutes,
                          from: start, through: end).map { ScheduleInterval(schedule: schedule, start: $0.start, end: $0.end) }
    }

    private func scheduleIntervals(
        days: [Int], startMinutes: Int, endMinutes: Int, from start: Date, through end: Date
    ) -> [(start: Date, end: Date)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start))!
        let lastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        var day = firstDay
        var output: [(Date, Date)] = []
        while day <= lastDay {
            if days.contains(calendar.component(.weekday, from: day)) {
                let intervalStart = calendar.date(byAdding: .minute, value: startMinutes, to: day)!
                let dayOffset = endMinutes == 24 * 60 ? 1 : (endMinutes > startMinutes ? 0 : 1)
                let endDay = calendar.date(byAdding: .day, value: dayOffset, to: day)!
                let normalizedEnd = endMinutes == 24 * 60 ? 0 : endMinutes
                let intervalEnd = calendar.date(byAdding: .minute, value: normalizedEnd, to: endDay)!
                if intervalEnd > start && intervalStart < end { output.append((intervalStart, intervalEnd)) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return output
    }

    private func scheduleIsActive(_ schedule: ParkingSchedule, at date: Date, isPublicHoliday: Bool) -> Bool {
        if isPublicHoliday && !schedule.appliesOnPublicHolidays { return false }
        let (weekday, minute) = localComponents(for: date)
        return windowMatches(days: schedule.days, start: schedule.startMinutes, end: schedule.endMinutes, weekday: weekday, minute: minute)
    }

    private func tariffIsActive(_ tariff: ParkingTariff, at date: Date) -> Bool {
        guard tariffIsEffective(tariff, at: date) else { return false }
        let (weekday, minute) = localComponents(for: date)
        return windowMatches(days: tariff.days, start: tariff.startMinutes, end: tariff.endMinutes, weekday: weekday, minute: minute)
    }

    private func tariffIsEffective(_ tariff: ParkingTariff, at date: Date) -> Bool {
        date >= tariff.effectiveFrom && (tariff.effectiveTo.map { date <= $0 } ?? true)
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

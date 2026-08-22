import Foundation

enum RestrictionResolution: Equatable, Sendable {
    case permitted(ParkingRule)
    case unrestricted
    case unsuitable
}

struct RestrictionEngine: Sendable {
    let timeZone: TimeZone

    init(timeZone: TimeZone = TimeZone(identifier: "Australia/Melbourne")!) {
        self.timeZone = timeZone
    }

    func rule(from rawCode: String) -> ParkingRule? {
        let code = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if code == "QP" { return ParkingRule(code: code, maxStayMinutes: 15, payment: .unknown) }
        if code == "FP15" { return ParkingRule(code: code, maxStayMinutes: 15, payment: .free) }
        if code == "1/4P" { return ParkingRule(code: code, maxStayMinutes: 15, payment: .unknown) }
        if code == "1/2P" { return ParkingRule(code: code, maxStayMinutes: 30, payment: .unknown) }

        let pattern = #"^(MP|FP)?([1-9][0-9]*)P$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
              let hoursRange = Range(match.range(at: 2), in: code),
              let hours = Int(code[hoursRange]) else { return nil }
        let prefixRange = Range(match.range(at: 1), in: code)
        let prefix = prefixRange.map { String(code[$0]) }
        let payment: ParkingPaymentStatus = prefix == "MP" ? .paid : (prefix == "FP" ? .free : .unknown)
        return ParkingRule(code: code, maxStayMinutes: hours * 60, payment: payment)
    }

    func activeRule(in records: [RestrictionRecord], at date: Date) -> ParkingRule? {
        records.first(where: { isActive($0, at: date) }).flatMap { rule(from: $0.display) }
    }

    func isEligible(_ rule: ParkingRule, for duration: StayDuration) -> Bool {
        rule.maxStayMinutes >= duration.rawValue
    }

    func resolve(_ records: [RestrictionRecord], at date: Date, for duration: StayDuration) -> RestrictionResolution {
        guard !records.isEmpty else { return .unsuitable }
        let active = records.filter { isActiveTime($0, at: date) }
        guard !active.isEmpty else { return .unrestricted }
        let rules = active.compactMap { rule(from: $0.display) }
        guard rules.count == active.count, rules.allSatisfy({ isEligible($0, for: duration) }) else { return .unsuitable }
        let tightest = rules.min(by: { $0.maxStayMinutes < $1.maxStayMinutes })!
        let payment: ParkingPaymentStatus = rules.contains(where: { $0.payment == .paid }) ? .paid : (rules.allSatisfy { $0.payment == .free } ? .free : .unknown)
        return .permitted(ParkingRule(code: tightest.code, maxStayMinutes: tightest.maxStayMinutes, payment: payment))
    }

    private func isActive(_ record: RestrictionRecord, at date: Date) -> Bool {
        guard rule(from: record.display) != nil else { return false }
        return isActiveTime(record, at: date)
    }

    private func isActiveTime(_ record: RestrictionRecord, at date: Date) -> Bool {
        guard let start = seconds(record.start), let finish = seconds(record.finish) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute, let second = components.second else { return false }
        let current = hour * 3600 + minute * 60 + second
        if start <= finish {
            return dayMatches(record.days, weekday: weekday) && current >= start && current < finish
        }
        if current >= start { return dayMatches(record.days, weekday: weekday) }
        let previous = weekday == 1 ? 7 : weekday - 1
        return current < finish && dayMatches(record.days, weekday: previous)
    }

    private func seconds(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + (parts.count > 2 ? parts[2] : 0)
    }

    private func dayMatches(_ raw: String, weekday: Int) -> Bool {
        let day = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"][weekday]!
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "Daily" { return true }
        if value == "Weekends" { return weekday == 1 || weekday == 7 }
        let indexes = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]
        if value.contains("-"), value.split(separator: "-").count == 2 {
            let parts = value.split(separator: "-").map(String.init)
            if let start = indexes[parts[0]], let end = indexes[parts[1]] {
                return start <= end ? (start...end).contains(weekday) : (weekday >= start || weekday <= end)
            }
        }
        return value.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.contains(day)
    }
}

@preconcurrency import UserNotifications
import Foundation

struct ParkingReminderMessage: Sendable {
    let title: String
    let body: String
}

enum ParkingReminderScheduleOutcome: Equatable, Sendable {
    case scheduled(Date)
    case denied
    case tooLate
    case unavailable
}

@MainActor
protocol ParkingReminderScheduling: AnyObject {
    func schedule(for session: ParkingSession, message: ParkingReminderMessage) async -> ParkingReminderScheduleOutcome
    func cancel(sessionID: UUID)
}

@MainActor
final class LocalParkingReminderScheduler: ParkingReminderScheduling {
    private let center: UNUserNotificationCenter
    private let now: () -> Date

    init(center: UNUserNotificationCenter = .current(), now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    func schedule(for session: ParkingSession, message: ParkingReminderMessage) async -> ParkingReminderScheduleOutcome {
        guard let departure = session.plannedDeparture else { return .tooLate }
        let currentDate = now()
        let leadTime = min(10 * 60, max(60, TimeInterval(session.durationMinutes * 6)))
        let fireDate = departure.addingTimeInterval(-leadTime)
        guard fireDate.timeIntervalSince(currentDate) >= 1 else { return .tooLate }

        do {
            let settings = await center.notificationSettings()
            let authorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authorized = true
            case .notDetermined:
                authorized = try await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                authorized = false
            @unknown default:
                authorized = false
            }
            guard authorized else { return .denied }

            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            content.userInfo = ["parkingSessionID": session.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireDate.timeIntervalSince(currentDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: ParkingReminderIdentifier.identifier(sessionID: session.id),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
            return .scheduled(fireDate)
        } catch {
            return .unavailable
        }
    }

    func cancel(sessionID: UUID) {
        let identifier = ParkingReminderIdentifier.identifier(sessionID: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

@MainActor
final class NoopParkingReminderScheduler: ParkingReminderScheduling {
    func schedule(for session: ParkingSession, message: ParkingReminderMessage) async -> ParkingReminderScheduleOutcome {
        .unavailable
    }

    func cancel(sessionID: UUID) {}
}

@MainActor
final class FixtureParkingReminderScheduler: ParkingReminderScheduling {
    func schedule(for session: ParkingSession, message: ParkingReminderMessage) async -> ParkingReminderScheduleOutcome {
        guard let departure = session.plannedDeparture else { return .tooLate }
        let fireDate = departure.addingTimeInterval(-5 * 60)
        guard fireDate.timeIntervalSinceNow >= 1 else { return .tooLate }
        return .scheduled(fireDate)
    }

    func cancel(sessionID: UUID) {}
}

@preconcurrency import ActivityKit
import AppIntents
import Foundation
@preconcurrency import UserNotifications

@available(iOS 17.0, *)
struct MarkParkedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "I'm parked" }
    static var description: IntentDescription {
        IntentDescription("Records that you parked. ParkAlong does not detect arrival.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Session")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        let sessionID = self.sessionID
        guard let uuid = UUID(uuidString: sessionID) else { return .result() }
        await Self.markParked(sessionID: sessionID, uuid: uuid, at: .now)
        return .result()
    }

    nonisolated private static func markParked(sessionID: String, uuid: UUID, at now: Date) async {
        let persisted = await MainActor.run { () -> ParkingSession? in
            guard var session = ParkingSessionPersistence.load(from: .standard), session.id == uuid else {
                return nil
            }
            session.markParked(at: now)
            ParkingSessionPersistence.save(session, to: .standard)
            return session
        }

        if let session = persisted {
            let content = ActivityContent(state: session.activityState, staleDate: session.activityStaleDate)
            for activity in Activity<ParkingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
                await activity.update(content)
            }
        }
    }
}

@available(iOS 17.0, *)
struct EndParkingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "End parking" }
    static var description: IntentDescription {
        IntentDescription("Clears this parking session from ParkAlong and the Lock Screen.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Session")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        let sessionID = self.sessionID
        guard let uuid = UUID(uuidString: sessionID) else { return .result() }
        await Self.endSession(sessionID: sessionID, uuid: uuid)
        return .result()
    }

    nonisolated private static func endSession(sessionID: String, uuid: UUID) async {
        // Cancel before clearing persistence/ending the activity so a stale
        // reminder can never fire after the session is gone. Covers both the
        // pending request and an already-delivered banner.
        // LiveActivityIntent performs in the app process, so UserDefaults
        // .standard and UNUserNotificationCenter.current() are intentional;
        // no App Group is used.
        let requestIdentifier = ParkingReminderIdentifier.identifier(sessionID: uuid)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        await MainActor.run {
            if let session = ParkingSessionPersistence.load(from: .standard), session.id == uuid {
                ParkingSessionPersistence.clear(from: .standard)
            }
        }
        for activity in Activity<ParkingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

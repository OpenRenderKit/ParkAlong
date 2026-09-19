@preconcurrency import ActivityKit
import Foundation

enum ParkingLiveActivityStartOutcome: Equatable, Sendable {
    case started
    case disabled
    case unavailable
}

@MainActor
protocol ParkingLiveActivityControlling: AnyObject {
    func start(_ session: ParkingSession) async -> ParkingLiveActivityStartOutcome
    func update(_ session: ParkingSession) async
    func end(sessionID: UUID) async
    func reconcile(with session: ParkingSession?) async
}

@MainActor
final class ActivityKitParkingLiveActivityController: ParkingLiveActivityControlling {
    private let authorizationInfo: ActivityAuthorizationInfo

    init(authorizationInfo: ActivityAuthorizationInfo = .init()) {
        self.authorizationInfo = authorizationInfo
    }

    func start(_ session: ParkingSession) async -> ParkingLiveActivityStartOutcome {
        guard authorizationInfo.areActivitiesEnabled else { return .disabled }
        await endAll(except: nil)
        do {
            _ = try Activity<ParkingActivityAttributes>.request(
                attributes: .init(sessionID: session.id.uuidString),
                content: content(for: session),
                pushType: nil
            )
            return .started
        } catch {
            return .unavailable
        }
    }

    func update(_ session: ParkingSession) async {
        await Self.push(
            sessionID: session.id.uuidString,
            content: content(for: session)
        )
    }

    func end(sessionID: UUID) async {
        await Self.finish(sessionID: sessionID.uuidString)
    }

    func reconcile(with session: ParkingSession?) async {
        guard let session else {
            await endAll(except: nil)
            return
        }
        await endAll(except: session.id)
        await update(session)
    }

    private func endAll(except sessionID: UUID?) async {
        await Self.finishAll(except: sessionID?.uuidString)
    }

    nonisolated private static func push(
        sessionID: String,
        content: ActivityContent<ParkingActivityAttributes.ContentState>
    ) async {
        for activity in Activity<ParkingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.update(content)
        }
    }

    nonisolated private static func finish(sessionID: String) async {
        for activity in Activity<ParkingActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated private static func finishAll(except sessionID: String?) async {
        for activity in Activity<ParkingActivityAttributes>.activities {
            guard activity.attributes.sessionID != sessionID else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func content(for session: ParkingSession) -> ActivityContent<ParkingActivityAttributes.ContentState> {
        .init(state: session.activityState, staleDate: session.activityStaleDate, relevanceScore: 10)
    }
}

@MainActor
final class NoopParkingLiveActivityController: ParkingLiveActivityControlling {
    func start(_ session: ParkingSession) async -> ParkingLiveActivityStartOutcome { .unavailable }
    func update(_ session: ParkingSession) async {}
    func end(sessionID: UUID) async {}
    func reconcile(with session: ParkingSession?) async {}
}

@MainActor
final class FixtureParkingLiveActivityController: ParkingLiveActivityControlling {
    private let outcome: ParkingLiveActivityStartOutcome

    init(outcome: ParkingLiveActivityStartOutcome) {
        self.outcome = outcome
    }

    func start(_ session: ParkingSession) async -> ParkingLiveActivityStartOutcome { outcome }
    func update(_ session: ParkingSession) async {}
    func end(sessionID: UUID) async {}
    func reconcile(with session: ParkingSession?) async {}
}

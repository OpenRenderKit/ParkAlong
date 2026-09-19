import Foundation

@MainActor
protocol ParkingSessionStoring: AnyObject {
    func load() -> ParkingSession?
    func save(_ session: ParkingSession)
    func clear()
}

@MainActor
final class UserDefaultsParkingSessionStore: ParkingSessionStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ParkingSession? {
        ParkingSessionPersistence.load(from: defaults)
    }

    func save(_ session: ParkingSession) {
        ParkingSessionPersistence.save(session, to: defaults)
    }

    func clear() {
        ParkingSessionPersistence.clear(from: defaults)
    }
}

@MainActor
final class InMemoryParkingSessionStore: ParkingSessionStoring {
    private var session: ParkingSession?

    init(session: ParkingSession? = nil) {
        self.session = session
    }

    func load() -> ParkingSession? { session }
    func save(_ session: ParkingSession) { self.session = session }
    func clear() { session = nil }
}

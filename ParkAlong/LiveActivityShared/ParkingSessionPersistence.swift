import Foundation

enum ParkingSessionPersistence {
    static let key = "active-parking-session-v1"

    static func load(from defaults: UserDefaults) -> ParkingSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(ParkingSession.self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    static func save(_ session: ParkingSession, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

import Foundation

enum ParkingSessionDeepLinkAction: Equatable {
    case details
    case returnToCar
}

struct ParkingSessionDeepLink: Equatable {
    let sessionID: UUID
    let action: ParkingSessionDeepLinkAction

    init(sessionID: UUID, action: ParkingSessionDeepLinkAction) {
        self.sessionID = sessionID
        self.action = action
    }

    init?(url: URL) {
        guard url.scheme == "parkalong", url.host == "session" else { return nil }
        let pathID = url.pathComponents.dropFirst().first
        guard let pathID, let sessionID = UUID(uuidString: pathID) else { return nil }
        self.sessionID = sessionID
        let actionValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "action" })?.value
        action = actionValue == "return" ? .returnToCar : .details
    }

    static func url(sessionID: UUID, action: ParkingSessionDeepLinkAction = .details) -> URL {
        var components = URLComponents()
        components.scheme = "parkalong"
        components.host = "session"
        components.path = "/\(sessionID.uuidString)"
        if action == .returnToCar {
            components.queryItems = [.init(name: "action", value: "return")]
        }
        return components.url!
    }

    static func url(sessionIDString: String, action: ParkingSessionDeepLinkAction = .details) -> URL? {
        UUID(uuidString: sessionIDString).map { url(sessionID: $0, action: action) }
    }
}

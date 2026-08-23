import Foundation

enum RemoteParkingConfiguration {
    static func baseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoValue: Any? = Bundle.main.object(forInfoDictionaryKey: "ParkAlongRemoteBaseURL")
    ) -> URL? {
        let raw = environment["PARKALONG_REMOTE_BASE_URL"] ?? (infoValue as? String)
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return URL(string: value)
    }
}

enum RemoteParkingError: Error, Equatable {
    case insecureBaseURL
    case invalidURL
    case invalidResponse
    case incompatibleSchema
    case oversizedResponse
    case duplicateIdentifier
    case outOfBounds
}

struct RemoteParkingQuery: Hashable, Sendable {
    let viewport: ParkingViewport
    let plan: ParkingPlan
    let catalogVersion: String

    func url(baseURL: URL) throws -> URL {
        guard baseURL.scheme?.lowercased() == "https" else { throw RemoteParkingError.insecureBaseURL }
        guard var components = URLComponents(url: baseURL.appending(path: "v1/parking"), resolvingAgainstBaseURL: false) else {
            throw RemoteParkingError.invalidURL
        }
        components.queryItems = [
            .init(name: "west", value: String(viewport.west)),
            .init(name: "south", value: String(viewport.south)),
            .init(name: "east", value: String(viewport.east)),
            .init(name: "north", value: String(viewport.north)),
            .init(name: "arrival", value: ISO8601DateFormatter().string(from: plan.arrival)),
            .init(name: "durationMinutes", value: String(plan.durationMinutes)),
            .init(name: "isPublicHoliday", value: String(plan.isPublicHoliday)),
            .init(name: "zoom", value: String(viewport.zoomLevel)),
            .init(name: "catalogVersion", value: catalogVersion),
        ]
        guard let url = components.url else { throw RemoteParkingError.invalidURL }
        return url
    }
}

struct RemoteParkingEnvelope: Decodable, Sendable {
    let schemaVersion: Int
    let dataVersion: String
    let modelVersion: String?
    let generatedAt: Date
    let cacheTTLSeconds: Int
    let nextCursor: String?
    let locations: [StaticParkingLocation]

    static func validate(_ locations: [StaticParkingLocation], in viewport: ParkingViewport) throws {
        var identifiers: Set<String> = []
        let allowed = viewport.padded(by: 0.25)
        for location in locations {
            guard !location.id.isEmpty, identifiers.insert(location.id).inserted else {
                throw RemoteParkingError.duplicateIdentifier
            }
            guard allowed.contains(location.coordinate) else { throw RemoteParkingError.outOfBounds }
        }
    }
}

struct RemoteParkingMerger {
    static func merge(
        bundled: [StaticParkingLocation],
        remote: [StaticParkingLocation]
    ) -> [StaticParkingLocation] {
        var byID = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
        for record in remote {
            guard let existing = byID[record.id] else {
                byID[record.id] = record
                continue
            }
            if record.source.checkedAt >= existing.source.checkedAt {
                byID[record.id] = record
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }
}

protocol RemoteParkingProviding: Sendable {
    func locations(for query: RemoteParkingQuery) async throws -> [StaticParkingLocation]
}

actor RemoteParkingClient: RemoteParkingProviding {
    private struct CacheEntry: Sendable {
        let locations: [StaticParkingLocation]
        let etag: String?
        let expiresAt: Date
    }

    private let baseURL: URL
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var cache: [RemoteParkingQuery: CacheEntry] = [:]

    init(
        baseURL: URL,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now }
    ) throws {
        guard baseURL.scheme?.lowercased() == "https" else { throw RemoteParkingError.insecureBaseURL }
        self.baseURL = baseURL
        self.session = session
        self.now = now
    }

    func locations(for query: RemoteParkingQuery) async throws -> [StaticParkingLocation] {
        let now = now()
        if let cached = cache[query], cached.expiresAt > now { return cached.locations }

        var request = URLRequest(url: try query.url(baseURL: baseURL))
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cache[query]?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteParkingError.invalidResponse }
        if http.statusCode == 304, let cached = cache[query] {
            let refreshed = CacheEntry(locations: cached.locations, etag: cached.etag, expiresAt: now.addingTimeInterval(120))
            cache[query] = refreshed
            return refreshed.locations
        }
        guard http.statusCode == 200 else { throw RemoteParkingError.invalidResponse }
        guard data.count <= 15_000_000 else { throw RemoteParkingError.oversizedResponse }

        let envelope = try BundleDataLoader.decoder().decode(RemoteParkingEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw RemoteParkingError.incompatibleSchema }
        try RemoteParkingEnvelope.validate(envelope.locations, in: query.viewport)
        let ttl = min(3_600, max(30, envelope.cacheTTLSeconds))
        let entry = CacheEntry(
            locations: envelope.locations,
            etag: http.value(forHTTPHeaderField: "ETag"),
            expiresAt: now.addingTimeInterval(TimeInterval(ttl))
        )
        cache[query] = entry
        return entry.locations
    }
}

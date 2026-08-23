import Foundation

enum BundleDataError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self { case .missing(let name): "Bundled parking data is missing: \(name)." }
    }
}

enum BundleDataLoader {
    static func load<T: Decodable>(_ type: T.Type, named name: String, bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw BundleDataError.missing(name) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = withFractional.date(from: raw) ?? standard.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
        }
        return try decoder.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

protocol ParkingRepositoryProviding: Sendable {
    func refresh(destination: Coordinate, duration: StayDuration, now: Date, force: Bool) async throws -> ParkingRepositoryResult
    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate]
}

extension ParkingRepository: ParkingRepositoryProviding {}

protocol StaticParkingProviding: Sendable {
    func options(near destination: Coordinate, duration: StayDuration, at date: Date) async -> [ParkingOption]
}

import Foundation

struct StaticCatalogManifest: Decodable, Equatable, Sendable {
    let generatedAt: Date
    let recordCount: Int
    let sourceCounts: [String: Int]
    let outputBytes: Int
    let outputSHA256: String

    var version: String { outputSHA256 }
}

enum BundleDataError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self { case .missing(let name): "Bundled parking data is missing: \(name)." }
    }
}

enum BundleDataLoader {
    static func load<T: Decodable>(_ type: T.Type, named name: String, bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw BundleDataError.missing(name) }
        return try decoder().decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func decoder() -> JSONDecoder {
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
        return decoder
    }
}

protocol ParkingRepositoryProviding: Sendable {
    func refresh(viewport: ParkingViewport, plan: ParkingPlan, now: Date, force: Bool) async throws -> ParkingRepositoryResult
    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate]
}

extension ParkingRepository: ParkingRepositoryProviding {}

protocol StaticParkingProviding: Sendable {
    func options(in viewport: ParkingViewport, plan: ParkingPlan) async -> [ParkingOption]
    func search(_ query: String, near viewport: ParkingViewport, plan: ParkingPlan, limit: Int) async -> [ParkingOption]
}

extension StaticParkingProviding {
    func search(_ query: String, near viewport: ParkingViewport, plan: ParkingPlan, limit: Int = 20) async -> [ParkingOption] { [] }
}

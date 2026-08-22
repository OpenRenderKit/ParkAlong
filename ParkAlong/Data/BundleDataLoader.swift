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
        return try JSONDecoder().decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

protocol ParkingRepositoryProviding: Sendable {
    func refresh(destination: Coordinate, duration: StayDuration, now: Date, force: Bool) async throws -> ParkingRepositoryResult
    func vacantBays(zoneNumber: Int, now: Date) async throws -> [Coordinate]
}

extension ParkingRepository: ParkingRepositoryProviding {}


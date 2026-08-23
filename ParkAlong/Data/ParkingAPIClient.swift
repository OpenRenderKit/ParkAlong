import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol ParkingAPIProviding: Sendable {
    func fetchZoneCounts(near coordinate: Coordinate, radiusMetres: Int, since: Date) async throws -> [SensorAggregateRow]
    func fetchVacantBays(zoneNumber: Int, since: Date) async throws -> [SensorReading]
}

struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ParkingAPIError.invalidResponse }
        return (data, http)
    }
}

enum ParkingAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case malformedData

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The City data request could not be created."
        case .invalidResponse: "The City data service returned an invalid response."
        case .httpStatus: "The City data service is temporarily unavailable."
        case .malformedData: "The City data response could not be read."
        }
    }
}

struct SensorPage: Sendable {
    let totalCount: Int
    let results: [SensorReading]
}

struct ParkingAPIClient: ParkingAPIProviding, Sendable {
    private let transport: any HTTPTransport
    private let pageSize: Int
    private let baseURL = URL(string: "https://data.melbourne.vic.gov.au/api/explore/v2.1/catalog/datasets/on-street-parking-bay-sensors/records")!
    fileprivate static let apiDateStyle = Date.ISO8601FormatStyle()

    init(transport: any HTTPTransport = URLSessionTransport(), pageSize: Int = 100) {
        self.transport = transport
        self.pageSize = pageSize
    }

    func fetchZoneCounts(near coordinate: Coordinate, radiusMetres: Int, since: Date) async throws -> [SensorAggregateRow] {
        var rows: [SensorAggregateRow] = []
        var offset = 0
        while true {
            let select = "zone_number, status_description, count(*) as bay_count, max(status_timestamp) as newest_timestamp"
            let whereClause = "within_distance(location, geom'POINT(\(coordinate.longitude) \(coordinate.latitude))', \(radiusMetres)m) AND status_timestamp >= date'\(Self.apiDate(since))' AND zone_number is not null"
            let request = try makeRequest(items: [
                .init(name: "select", value: select),
                .init(name: "where", value: whereClause),
                .init(name: "group_by", value: "zone_number, status_description"),
                .init(name: "order_by", value: "zone_number"),
                .init(name: "limit", value: String(pageSize)),
                .init(name: "offset", value: String(offset))
            ])
            let data = try await validatedData(for: request)
            let page = try Self.decodeAggregatePage(data)
            rows.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += pageSize
        }
        return rows
    }

    func fetchVacantBays(zoneNumber: Int, since: Date) async throws -> [SensorReading] {
        var rows: [SensorReading] = []
        var offset = 0
        while true {
            let whereClause = "zone_number = \(zoneNumber) AND status_description = 'Unoccupied' AND status_timestamp >= date'\(Self.apiDate(since))'"
            let request = try makeRequest(items: [
                .init(name: "where", value: whereClause),
                .init(name: "limit", value: String(pageSize)),
                .init(name: "offset", value: String(offset))
            ])
            let data = try await validatedData(for: request)
            let page = try Self.decodeSensorPage(data)
            rows.append(contentsOf: page.results)
            guard page.results.count == pageSize else { break }
            offset += pageSize
        }
        return rows
    }

    static func decodeSensorPage(_ data: Data) throws -> SensorPage {
        do {
            let decoded = try JSONDecoder().decode(SensorEnvelope.self, from: data)
            return SensorPage(totalCount: decoded.totalCount, results: decoded.results.map(\.domain))
        } catch {
            throw ParkingAPIError.malformedData
        }
    }

    private static func decodeAggregatePage(_ data: Data) throws -> [SensorAggregateRow] {
        do {
            return try JSONDecoder().decode(AggregateEnvelope.self, from: data).results.map(\.domain)
        } catch {
            throw ParkingAPIError.malformedData
        }
    }

    private func makeRequest(items: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw ParkingAPIError.invalidURL }
        components.queryItems = items
        guard let url = components.url else { throw ParkingAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("ParkAlong/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw ParkingAPIError.httpStatus(response.statusCode) }
        return data
    }

    private static func apiDate(_ date: Date) -> String {
        date.formatted(apiDateStyle)
    }
}

private struct SensorEnvelope: Decodable {
    let totalCount: Int
    let results: [SensorDTO]
    enum CodingKeys: String, CodingKey { case totalCount = "total_count", results }
}

private struct SensorDTO: Decodable {
    let statusTimestamp: String
    let zoneNumber: Int?
    let statusDescription: String
    let kerbsideID: Int
    let location: LocationDTO

    enum CodingKeys: String, CodingKey {
        case statusTimestamp = "status_timestamp"
        case zoneNumber = "zone_number"
        case statusDescription = "status_description"
        case kerbsideID = "kerbsideid"
        case location
    }

    var domain: SensorReading {
        SensorReading(
            kerbsideID: kerbsideID,
            zoneNumber: zoneNumber,
            status: SensorStatus(apiValue: statusDescription),
            timestamp: (try? Date(statusTimestamp, strategy: ParkingAPIClient.apiDateStyle)) ?? .distantPast,
            coordinate: .init(latitude: location.lat, longitude: location.lon)
        )
    }
}

private struct LocationDTO: Decodable { let lon: Double; let lat: Double }

private struct AggregateEnvelope: Decodable { let results: [AggregateDTO] }

private struct AggregateDTO: Decodable {
    let zoneNumber: Int
    let statusDescription: String
    let bayCount: Int
    let newestTimestamp: String
    enum CodingKeys: String, CodingKey {
        case zoneNumber = "zone_number"
        case statusDescription = "status_description"
        case bayCount = "bay_count"
        case newestTimestamp = "newest_timestamp"
    }
    var domain: SensorAggregateRow {
        SensorAggregateRow(
            zoneNumber: zoneNumber,
            status: SensorStatus(apiValue: statusDescription),
            bayCount: bayCount,
            newestTimestamp: (try? Date(newestTimestamp, strategy: ParkingAPIClient.apiDateStyle)) ?? .distantPast
        )
    }
}

import XCTest
@testable import ParkAlong

final class RemoteParkingRepositoryTests: XCTestCase {
    func testRemoteConfigurationSupportsBuildSettingAndEnvironmentOverride() {
        let buildConfigured = RemoteParkingConfiguration.baseURL(environment: [:], infoValue: "https://parking.example.com")
        let overridden = RemoteParkingConfiguration.baseURL(
            environment: ["PARKALONG_REMOTE_BASE_URL": "https://preview.example.com"],
            infoValue: "https://parking.example.com"
        )

        XCTAssertEqual(buildConfigured?.absoluteString, "https://parking.example.com")
        XCTAssertEqual(overridden?.absoluteString, "https://preview.example.com")
        XCTAssertNil(RemoteParkingConfiguration.baseURL(environment: [:], infoValue: "  "))
    }

    private let arrival = Date(timeIntervalSince1970: 1_777_000_000)

    func testQueryURLCarriesViewportArrivalDurationZoomAndCatalogVersion() throws {
        let query = RemoteParkingQuery(
            viewport: .init(south: -38, west: 144, north: -37, east: 145, zoomLevel: 12.5),
            plan: .init(arrival: arrival, durationMinutes: 95, isPublicHoliday: true),
            catalogVersion: "sha256:abc"
        )

        let url = try query.url(baseURL: URL(string: "https://parking.example")!)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(components.path, "/v1/parking")
        XCTAssertEqual(values["south"], "-38.0")
        XCTAssertEqual(values["durationMinutes"], "95")
        XCTAssertEqual(values["zoom"], "12.5")
        XCTAssertEqual(values["catalogVersion"], "sha256:abc")
        XCTAssertEqual(values["isPublicHoliday"], "true")
        XCTAssertNotNil(values["arrival"])
    }

    func testRemoteMergeUsesStableIDAndNeverLetsAnOlderDeltaReplaceNewerBundledEvidence() {
        let bundledNew = location(id: "same", checkedAt: arrival)
        let remoteOld = location(id: "same", checkedAt: arrival.addingTimeInterval(-60))
        let remoteNew = location(id: "new", checkedAt: arrival.addingTimeInterval(60))

        let merged = RemoteParkingMerger.merge(bundled: [bundledNew], remote: [remoteOld, remoteNew])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first(where: { $0.id == "same" })?.source.checkedAt, arrival)
        XCTAssertNotNil(merged.first(where: { $0.id == "new" }))
    }

    func testEnvelopeValidationRejectsDuplicateIDsAndOutOfBoundsCoordinates() {
        let viewport = ParkingViewport(south: -38, west: 144, north: -37, east: 145, zoomLevel: 12)
        let duplicate = location(id: "same", checkedAt: arrival)
        let outside = location(id: "outside", coordinate: .init(latitude: -35, longitude: 145), checkedAt: arrival)

        XCTAssertThrowsError(try RemoteParkingEnvelope.validate([duplicate, duplicate], in: viewport))
        XCTAssertThrowsError(try RemoteParkingEnvelope.validate([outside], in: viewport))
    }

    func testExpiredCacheRevalidatesWithETagAndAcceptsNotModified() async throws {
        let expected = location(id: "remote", checkedAt: arrival)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(TestRemoteEnvelope(
            schemaVersion: 1,
            dataVersion: "delta-1",
            modelVersion: nil,
            generatedAt: arrival,
            cacheTTLSeconds: 30,
            nextCursor: nil,
            locations: [expected]
        ))
        MockRemoteURLProtocol.state.reset(with: [
            .init(statusCode: 200, headers: ["ETag": "\"delta-1\""], data: payload),
            .init(statusCode: 304, headers: [:], data: Data()),
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRemoteURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let clock = LockedTestClock(arrival)
        let client = try RemoteParkingClient(
            baseURL: URL(string: "https://parking.example")!,
            session: session,
            now: { clock.value }
        )
        let query = RemoteParkingQuery(
            viewport: .init(south: -38, west: 144, north: -37, east: 145, zoomLevel: 12),
            plan: .init(arrival: arrival, durationMinutes: 60),
            catalogVersion: "bundled-1"
        )

        let first = try await client.locations(for: query)
        clock.advance(by: 31)
        let second = try await client.locations(for: query)
        let requests = MockRemoteURLProtocol.state.requests

        XCTAssertEqual(first, [expected])
        XCTAssertEqual(second, [expected])
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), "\"delta-1\"")
    }

    func testRemoteFailureFallsBackToBundledParking() async {
        let bundled = location(id: "bundled", checkedAt: arrival)
        let repository = StaticParkingRepository(
            locations: [bundled],
            remote: FailingRemoteParkingProvider()
        )
        let viewport = ParkingViewport(south: -38, west: 144, north: -37, east: 145, zoomLevel: 14)
        let plan = ParkingPlan(arrival: arrival, durationMinutes: 60)

        let options = await repository.options(in: viewport, plan: plan)

        XCTAssertEqual(options.map(\.id), ["static-bundled"])
    }

    func testStaticRepositoryDoesNotHideRemoteRefreshBehindItsViewportCache() async {
        let first = location(id: "changing", checkedAt: arrival, capacity: 10)
        let second = location(id: "changing", checkedAt: arrival.addingTimeInterval(60), capacity: 20)
        let remote = SequenceRemoteParkingProvider(responses: [[first], [second]])
        let repository = StaticParkingRepository(locations: [], remote: remote)
        let viewport = ParkingViewport(south: -38, west: 144, north: -37, east: 145, zoomLevel: 14)
        let plan = ParkingPlan(arrival: arrival, durationMinutes: 60)

        let firstOptions = await repository.options(in: viewport, plan: plan)
        let secondOptions = await repository.options(in: viewport, plan: plan)
        let requestCount = await remote.requestCount

        XCTAssertEqual(firstOptions.first?.total, 10)
        XCTAssertEqual(secondOptions.first?.total, 20)
        XCTAssertEqual(requestCount, 2)
    }

    private func location(
        id: String,
        coordinate: Coordinate = .melbourneCBD,
        checkedAt: Date,
        capacity: Int = 10
    ) -> StaticParkingLocation {
        .init(
            id: id, name: id, municipality: "Fixture", coordinate: coordinate,
            kind: .offStreet, archetype: .general, capacity: capacity, accessibleSpaces: nil,
            schedules: [], tariffs: [],
            source: .init(
                id: "fixture", name: "Fixture", sourceURL: URL(string: "https://example.com")!,
                licenseName: "Fixture", licenseURL: nil, datasetUpdatedAt: checkedAt, checkedAt: checkedAt
            ),
            classification: .staticOnly, predictionEvidence: nil
        )
    }
}

private struct TestRemoteEnvelope: Encodable {
    let schemaVersion: Int
    let dataVersion: String
    let modelVersion: String?
    let generatedAt: Date
    let cacheTTLSeconds: Int
    let nextCursor: String?
    let locations: [StaticParkingLocation]
}

private actor FailingRemoteParkingProvider: RemoteParkingProviding {
    func locations(for query: RemoteParkingQuery) async throws -> [StaticParkingLocation] {
        throw RemoteParkingError.invalidResponse
    }
}

private actor SequenceRemoteParkingProvider: RemoteParkingProviding {
    private var responses: [[StaticParkingLocation]]
    private(set) var requestCount = 0

    init(responses: [[StaticParkingLocation]]) {
        self.responses = responses
    }

    func locations(for query: RemoteParkingQuery) async throws -> [StaticParkingLocation] {
        requestCount += 1
        return responses.isEmpty ? [] : responses.removeFirst()
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        lock.withLock { storedValue }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { storedValue = storedValue.addingTimeInterval(interval) }
    }
}

private final class MockRemoteURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let data: Data
    }

    static let state = State()

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [Stub] = []
        private var receivedRequests: [URLRequest] = []

        var requests: [URLRequest] {
            lock.withLock { receivedRequests }
        }

        func reset(with stubs: [Stub]) {
            lock.withLock {
                self.stubs = stubs
                receivedRequests = []
            }
        }

        func response(for request: URLRequest) -> Stub? {
            lock.withLock {
                receivedRequests.append(request)
                return stubs.isEmpty ? nil : stubs.removeFirst()
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.state.response(for: request),
              let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: RemoteParkingError.invalidResponse)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.data.isEmpty {
            client?.urlProtocol(self, didLoad: stub.data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

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

    func testRemoteCacheEvictsLeastRecentlyUsedQueriesAndRefreshesRecencyOnHits() async throws {
        let expected = location(id: "remote", checkedAt: arrival)
        let payload = try remoteEnvelopeData(locations: [expected])
        let clock = LockedTestClock(arrival)
        let client = try makeRemoteClient(
            stubs: [
                .init(statusCode: 200, headers: ["ETag": "\"a\""], data: payload),
                .init(statusCode: 200, headers: ["ETag": "\"b\""], data: payload),
                .init(statusCode: 200, headers: ["ETag": "\"c\""], data: payload),
                .init(statusCode: 200, headers: ["ETag": "\"b2\""], data: payload),
            ],
            clock: clock,
            cacheLimit: 2
        )
        let queryA = remoteQuery(offset: 0)
        let queryB = remoteQuery(offset: 0.01)
        let queryC = remoteQuery(offset: 0.02)

        let firstA = try await client.locations(for: queryA)
        let firstB = try await client.locations(for: queryB)
        let hitA = try await client.locations(for: queryA)
        let firstC = try await client.locations(for: queryC)
        let retainedA = try await client.locations(for: queryA)
        let evictedB = try await client.locations(for: queryB)
        let requests = MockRemoteURLProtocol.state.requests

        XCTAssertEqual(firstA, [expected])
        XCTAssertEqual(firstB, [expected])
        XCTAssertEqual(hitA, [expected])
        XCTAssertEqual(firstC, [expected])
        XCTAssertEqual(retainedA, [expected])
        XCTAssertEqual(evictedB, [expected])
        XCTAssertEqual(requests.count, 4)
        XCTAssertNil(requests[3].value(forHTTPHeaderField: "If-None-Match"))
    }

    func testNotModifiedResponseRefreshesRemoteCacheRecency() async throws {
        let expected = location(id: "remote", checkedAt: arrival)
        let payload = try remoteEnvelopeData(locations: [expected])
        let clock = LockedTestClock(arrival)
        let client = try makeRemoteClient(
            stubs: [
                .init(statusCode: 200, headers: ["ETag": "\"a\""], data: payload),
                .init(statusCode: 200, headers: ["ETag": "\"b\""], data: payload),
                .init(statusCode: 304, headers: [:], data: Data()),
                .init(statusCode: 200, headers: ["ETag": "\"c\""], data: payload),
                .init(statusCode: 200, headers: ["ETag": "\"b2\""], data: payload),
            ],
            clock: clock,
            cacheLimit: 2
        )
        let queryA = remoteQuery(offset: 0)
        let queryB = remoteQuery(offset: 0.01)
        let queryC = remoteQuery(offset: 0.02)

        let firstA = try await client.locations(for: queryA)
        let firstB = try await client.locations(for: queryB)
        clock.advance(by: 31)
        let revalidatedA = try await client.locations(for: queryA)
        let firstC = try await client.locations(for: queryC)
        let retainedA = try await client.locations(for: queryA)
        let evictedB = try await client.locations(for: queryB)
        let requests = MockRemoteURLProtocol.state.requests

        XCTAssertEqual(firstA, [expected])
        XCTAssertEqual(firstB, [expected])
        XCTAssertEqual(revalidatedA, [expected])
        XCTAssertEqual(firstC, [expected])
        XCTAssertEqual(retainedA, [expected])
        XCTAssertEqual(evictedB, [expected])
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "If-None-Match"), "\"a\"")
        XCTAssertNil(requests[4].value(forHTTPHeaderField: "If-None-Match"))
    }

    func testCancelledRemoteLookupStopsBeforeDecodeAndDoesNotCache() async throws {
        let expected = location(id: "remote", checkedAt: arrival)
        let payload = try remoteEnvelopeData(locations: [expected])
        let clock = LockedTestClock(arrival)
        let client = try makeRemoteClient(
            stubs: [.init(statusCode: 200, headers: ["ETag": "\"stale\""], data: Data("{not-json".utf8))],
            clock: clock,
            holdResponses: true
        )
        let query = remoteQuery()

        let lookup = Task { try await client.locations(for: query) }
        await MockRemoteURLProtocol.state.waitUntilRequestCount(1)
        lookup.cancel()
        MockRemoteURLProtocol.state.releaseHeldResponses()

        do {
            _ = try await lookup.value
            XCTFail("Cancelled remote lookup should not complete")
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            XCTFail("Cancelled remote lookup should not decode or fail as \(error)")
        }

        MockRemoteURLProtocol.state.reset(with: [
            .init(statusCode: 200, headers: ["ETag": "\"fresh\""], data: payload)
        ])
        let recovered = try await client.locations(for: query)
        let requests = MockRemoteURLProtocol.state.requests

        XCTAssertEqual(recovered, [expected])
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "If-None-Match"))
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

    private func remoteQuery(offset: Double = 0) -> RemoteParkingQuery {
        RemoteParkingQuery(
            viewport: .init(south: -38 + offset, west: 144, north: -37 + offset, east: 145, zoomLevel: 12),
            plan: .init(arrival: arrival, durationMinutes: 60),
            catalogVersion: "bundled-1"
        )
    }

    private func remoteEnvelopeData(locations: [StaticParkingLocation], ttl: Int = 30) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(TestRemoteEnvelope(
            schemaVersion: 1,
            dataVersion: "delta-1",
            modelVersion: nil,
            generatedAt: arrival,
            cacheTTLSeconds: ttl,
            nextCursor: nil,
            locations: locations
        ))
    }

    private func makeRemoteClient(
        stubs: [MockRemoteURLProtocol.Stub],
        clock: LockedTestClock,
        cacheLimit: Int = 16,
        holdResponses: Bool = false
    ) throws -> RemoteParkingClient {
        MockRemoteURLProtocol.state.reset(with: stubs, holdResponses: holdResponses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockRemoteURLProtocol.self]
        return try RemoteParkingClient(
            baseURL: URL(string: "https://parking.example")!,
            session: URLSession(configuration: configuration),
            now: { clock.value },
            cacheLimit: cacheLimit
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
    private let loadingLock = NSLock()
    private var stopped = false

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [Stub] = []
        private var receivedRequests: [URLRequest] = []
        private var holdResponses = false

        var requests: [URLRequest] {
            lock.withLock { receivedRequests }
        }

        func reset(with stubs: [Stub], holdResponses: Bool = false) {
            lock.withLock {
                self.stubs = stubs
                receivedRequests = []
                self.holdResponses = holdResponses
            }
        }

        func waitUntilRequestCount(_ count: Int) async {
            while true {
                let ready = lock.withLock { receivedRequests.count >= count }
                if ready { return }
                await Task.yield()
            }
        }

        func waitIfHolding() {
            while lock.withLock({ holdResponses }) {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }

        func releaseHeldResponses() {
            lock.withLock { holdResponses = false }
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
        guard let stub = Self.state.response(for: request) else {
            client?.urlProtocol(self, didFailWithError: RemoteParkingError.invalidResponse)
            return
        }
        Self.state.waitIfHolding()
        deliverIfNeeded(stub)
    }

    override func stopLoading() {
        loadingLock.withLock { stopped = true }
        Self.state.releaseHeldResponses()
    }

    private func deliverIfNeeded(_ stub: Stub) {
        let stopped = loadingLock.withLock { self.stopped }
        guard !stopped else { return }
        guard let response = HTTPURLResponse(
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
}

import XCTest
@testable import ParkAlong

final class ParkingAPIClientTests: XCTestCase {
    func testDecodesRealSensorFields() throws {
        let data = Data(#"{"total_count":1,"results":[{"lastupdated":"2026-08-15T00:35:40+00:00","status_timestamp":"2026-08-15T00:34:55+00:00","zone_number":7556,"status_description":"Unoccupied","kerbsideid":65145,"location":{"lon":144.9686441031432,"lat":-37.810412827837034}}]}"#.utf8)

        let page = try ParkingAPIClient.decodeSensorPage(data)

        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(page.results.first?.kerbsideID, 65145)
        XCTAssertEqual(page.results.first?.zoneNumber, 7556)
        XCTAssertEqual(page.results.first?.status, .unoccupied)
        XCTAssertEqual(page.results.first?.coordinate.latitude, -37.810412827837034)
    }

    func testAggregatePaginationContinuesUntilShortPage() async throws {
        let first = Data(#"{"total_count":2,"results":[{"zone_number":7001,"status_description":"Present","bay_count":3,"newest_timestamp":"2026-08-15T00:34:55+00:00"}]}"#.utf8)
        let second = Data(#"{"total_count":1,"results":[]}"#.utf8)
        let transport = RecordingTransport(responses: [first, second])
        let client = ParkingAPIClient(transport: transport, pageSize: 1)

        let rows = try await client.fetchZoneCounts(near: .melbourneCBD, radiusMetres: 700, since: Date(timeIntervalSince1970: 1_776_297_600))

        XCTAssertEqual(rows.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url!.absoluteString.contains("offset=0"))
        XCTAssertTrue(requests[1].url!.absoluteString.contains("offset=1"))
        XCTAssertTrue(requests[0].url!.absoluteString.contains("within_distance"))
    }

    func testVacantBayRequestScopesStatusAndZone() async throws {
        let body = Data(#"{"total_count":0,"results":[]}"#.utf8)
        let transport = RecordingTransport(responses: [body])
        let client = ParkingAPIClient(transport: transport)

        _ = try await client.fetchVacantBays(zoneNumber: 7311, since: Date(timeIntervalSince1970: 1_776_297_600))

        let url = await transport.requests.first!.url!.absoluteString.removingPercentEncoding!
        XCTAssertTrue(url.contains("zone_number = 7311"))
        XCTAssertTrue(url.contains("status_description = 'Unoccupied'"))
    }

    func testAggregateCancellationStopsPagination() async throws {
        let firstPage = Data(#"{"total_count":2,"results":[{"zone_number":7001,"status_description":"Present","bay_count":3,"newest_timestamp":"2026-08-15T00:34:55+00:00"}]}"#.utf8)
        let transport = CancellationGatedTransport(firstPage: firstPage)
        let client = ParkingAPIClient(transport: transport, pageSize: 1)

        let fetchTask = Task { try await client.fetchZoneCounts(near: .melbourneCBD, radiusMetres: 700, since: Date(timeIntervalSince1970: 1_776_297_600)) }
        await transport.waitForFirstRequest()
        fetchTask.cancel()
        await transport.releaseFirstRequest()

        do {
            _ = try await fetchTask.value
            XCTFail("Expected CancellationError instead of a partial result")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "Cancellation must stop further page work")
    }
}

actor RecordingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [Data]

    init(responses: [Data]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = responses.isEmpty ? Data(#"{"total_count":0,"results":[]}"#.utf8) : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

actor CancellationGatedTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let firstPage: Data
    private var didStartFirstRequest = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var canFinishFirstRequest = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(firstPage: Data) { self.firstPage = firstPage }

    func waitForFirstRequest() async {
        if didStartFirstRequest { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() async {
        canFinishFirstRequest = true
        let waiters = finishWaiters
        finishWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if requests.count == 1 {
            didStartFirstRequest = true
            let waiters = startWaiters
            startWaiters = []
            for waiter in waiters { waiter.resume() }
            if !canFinishFirstRequest {
                await withCheckedContinuation { continuation in
                    finishWaiters.append(continuation)
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (firstPage, response)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(#"{"results":[]}"#.utf8), response)
    }
}

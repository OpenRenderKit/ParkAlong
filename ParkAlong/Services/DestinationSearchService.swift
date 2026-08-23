@preconcurrency import MapKit
import Foundation

enum ParkingDestinationKind: String, Hashable, Sendable {
    case place
    case parking
}

struct ParkingDestination: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: Coordinate
    let kind: ParkingDestinationKind
    let parkingOptionID: String?

    init(
        id: String,
        name: String,
        subtitle: String,
        coordinate: Coordinate,
        kind: ParkingDestinationKind = .place,
        parkingOptionID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.kind = kind
        self.parkingOptionID = parkingOptionID
    }
}

@MainActor
protocol DestinationSearching: Sendable {
    func search(_ query: String, in viewport: ParkingViewport) async throws -> [ParkingDestination]
}

enum DestinationSearchRanker {
    static func rank(
        _ results: [ParkingDestination],
        query: String,
        viewport: ParkingViewport
    ) -> [ParkingDestination] {
        let normalizedQuery = normalize(query)
        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        return results.enumerated().sorted { lhs, rhs in
            let left = score(lhs.element, normalizedQuery: normalizedQuery, queryTokens: queryTokens, viewport: viewport)
            let right = score(rhs.element, normalizedQuery: normalizedQuery, queryTokens: queryTokens, viewport: viewport)
            if left == right { return lhs.offset < rhs.offset }
            return left > right
        }.map(\.element)
    }

    private static func score(
        _ result: ParkingDestination,
        normalizedQuery: String,
        queryTokens: Set<String>,
        viewport: ParkingViewport
    ) -> Double {
        let name = normalize(result.name)
        let subtitle = normalize(result.subtitle)
        let resultTokens = Set((name + " " + subtitle).split(separator: " ").map(String.init))
        let tokenCoverage = queryTokens.isEmpty ? 0 : Double(queryTokens.intersection(resultTokens).count) / Double(queryTokens.count)
        let exact = name == normalizedQuery ? 1.0 : 0
        let prefix = name.hasPrefix(normalizedQuery) || normalizedQuery.hasPrefix(name) ? 0.75 : 0
        let contains = name.contains(normalizedQuery) ? 0.55 : 0
        let text = max(exact, prefix, contains, tokenCoverage * 0.7)
        let distance = ParkingRepository.distance(from: result.coordinate, to: viewport.center)
        let proximity = max(0, 1 - min(distance, 50_000) / 50_000)
        let explicitParkingIntent = normalizedQuery.contains("parking") || normalizedQuery.contains("car park")
        let parkingBoost = result.kind == .parking ? (explicitParkingIntent ? 0.18 : 0.05) : 0
        return text * 0.82 + proximity * 0.13 + parkingBoost
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

@MainActor
final class DestinationSearchService: NSObject, DestinationSearching, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var completionContinuation: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    private var completionTimeoutTask: Task<Void, Never>?
    private var completionRequestID = UUID()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.pointOfInterestFilter = .includingAll
    }

    func search(_ query: String, in viewport: ParkingViewport) async throws -> [ParkingDestination] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let region = Self.region(for: viewport)
        let completions = await completions(for: trimmed, region: region)
        var destinations: [ParkingDestination] = []
        var seen: Set<String> = []

        for completion in completions.prefix(10) {
            guard !Task.isCancelled else { return [] }
            let request = MKLocalSearch.Request(completion: completion)
            request.region = region
            request.resultTypes = [.address, .pointOfInterest]
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems.prefix(2) {
                let destination = Self.destination(from: item)
                if seen.insert(destination.id).inserted { destinations.append(destination) }
            }
        }

        if destinations.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.region = region
            request.resultTypes = [.address, .pointOfInterest]
            let response = try await MKLocalSearch(request: request).start()
            destinations = response.mapItems.map(Self.destination(from:))
        }
        return Array(DestinationSearchRanker.rank(destinations, query: trimmed, viewport: viewport).prefix(20))
    }

    private func completions(for query: String, region: MKCoordinateRegion) async -> [MKLocalSearchCompletion] {
        completionTimeoutTask?.cancel()
        completionContinuation?.resume(returning: [])
        completionContinuation = nil
        let requestID = UUID()
        completionRequestID = requestID
        completer.region = region
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completionContinuation = continuation
                completer.queryFragment = query
                completionTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(1.5))
                    } catch {
                        return
                    }
                    guard let self, self.completionRequestID == requestID else { return }
                    self.finishCompletions(with: [])
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishCompletions(with: [])
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        finishCompletions(with: completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        finishCompletions(with: [])
    }

    private func finishCompletions(with results: sending [MKLocalSearchCompletion]) {
        completionTimeoutTask?.cancel()
        completionTimeoutTask = nil
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume(returning: results)
    }

    private static func destination(from item: MKMapItem) -> ParkingDestination {
        let coordinate = item.placemark.coordinate
        return ParkingDestination(
            id: "\(coordinate.latitude),\(coordinate.longitude)",
            name: item.name ?? item.placemark.title ?? "Destination",
            subtitle: item.placemark.title ?? item.placemark.locality ?? "Victoria",
            coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    private static func region(for viewport: ParkingViewport) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: viewport.center.locationCoordinate,
            span: .init(latitudeDelta: viewport.latitudeSpan, longitudeDelta: viewport.longitudeSpan)
        )
    }
}

@MainActor
struct FixtureDestinationSearchService: DestinationSearching {
    func search(_ query: String, in viewport: ParkingViewport) async throws -> [ParkingDestination] {
        guard !query.isEmpty else { return [] }
        return [.init(
            id: "flinders", name: "Flinders Street Station", subtitle: "Flinders St, Melbourne",
            coordinate: .init(latitude: -37.8183, longitude: 144.9671)
        )]
    }
}

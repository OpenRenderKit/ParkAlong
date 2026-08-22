@preconcurrency import MapKit
import Foundation

struct ParkingDestination: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: Coordinate
}

protocol DestinationSearching: Sendable {
    func search(_ query: String) async throws -> [ParkingDestination]
}

final class DestinationSearchService: DestinationSearching, @unchecked Sendable {
    func search(_ query: String) async throws -> [ParkingDestination] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -37.8136, longitude: 144.9631), latitudinalMeters: 12_000, longitudinalMeters: 12_000)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(6).map { item in
            let coordinate = item.placemark.coordinate
            return ParkingDestination(
                id: "\(coordinate.latitude),\(coordinate.longitude)",
                name: item.name ?? item.placemark.title ?? "Destination",
                subtitle: item.placemark.title ?? "Melbourne",
                coordinate: .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }
}

struct FixtureDestinationSearchService: DestinationSearching {
    func search(_ query: String) async throws -> [ParkingDestination] {
        guard !query.isEmpty else { return [] }
        return [.init(id: "flinders", name: "Flinders Street Station", subtitle: "Flinders St, Melbourne", coordinate: .init(latitude: -37.8183, longitude: 144.9671))]
    }
}

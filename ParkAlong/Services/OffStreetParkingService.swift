@preconcurrency import MapKit
import Foundation

protocol OffStreetParkingProviding: Sendable {
    func options(near destination: Coordinate) async -> [ParkingOption]
}

final class OffStreetParkingService: OffStreetParkingProviding, @unchecked Sendable {
    func options(near destination: Coordinate) async -> [ParkingOption] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "parking garage"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: destination.locationCoordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(6).map { item in
            let coordinate = Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            let name = item.name ?? "Off-street parking"
            let provider = OffStreetProviderResolver.resolve(name: name, suppliedURL: item.url)
            let price = ParkingPriceInformation(
                primaryText: "Check current price", detail: "Live tariffs and spaces are managed by the facility",
                provider: provider.provider, actionLabel: provider.url == nil ? nil : "Check price / Book with provider", actionURL: provider.url
            )
            return ParkingOption(
                id: "facility-\(coordinate.latitude)-\(coordinate.longitude)", kind: .offStreet, title: name,
                locationLabel: item.placemark.title ?? name, coordinate: coordinate, availabilityState: .unknown,
                available: nil, total: nil, restrictionLabel: "Check facility stay terms", restrictionWindow: "Provider hours apply", activeNow: true,
                price: price, provider: provider.provider, sourceTimestamp: nil,
                walkingMetres: ParkingRepository.distance(from: coordinate, to: destination), prediction: nil, isBestBet: false, zoneNumber: nil,
                classification: .staticOnly, warningText: "Location only · availability is not live",
                sourceDatasetAt: nil, sourceCheckedAt: nil
            )
        }
    }
}

struct FixtureOffStreetParkingService: OffStreetParkingProviding {
    var includeResult = true

    func options(near destination: Coordinate) async -> [ParkingOption] {
        guard includeResult else { return [] }
        let coordinate = Coordinate(latitude: destination.latitude + 0.0028, longitude: destination.longitude - 0.001)
        let url = URL(string: "https://www.wilsonparking.com.au")!
        return [.init(
            id: "facility-wilson", kind: .offStreet, title: "Wilson Parking",
            locationLabel: "180 Russell Street, Melbourne", coordinate: coordinate, availabilityState: .unknown,
            available: nil, total: nil, restrictionLabel: "Facility terms apply", restrictionWindow: "Open now · verify with provider", activeNow: true,
            price: .init(primaryText: "Check current price", detail: "Dynamic facility pricing", provider: "Wilson Parking", actionLabel: "Check price / Book with provider", actionURL: url),
            provider: "Wilson Parking", sourceTimestamp: nil, walkingMetres: 420, prediction: nil, isBestBet: false, zoneNumber: nil,
            classification: .staticOnly, warningText: "Location only · availability is not live",
            sourceDatasetAt: nil, sourceCheckedAt: nil
        )]
    }
}

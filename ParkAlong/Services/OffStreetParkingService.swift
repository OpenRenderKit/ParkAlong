@preconcurrency import MapKit
import Foundation

protocol OffStreetParkingProviding: Sendable {
    func options(in viewport: ParkingViewport) async -> [ParkingOption]
}

final class OffStreetParkingService: OffStreetParkingProviding, @unchecked Sendable {
    func options(in viewport: ParkingViewport) async -> [ParkingOption] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "parking garage"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: viewport.center.locationCoordinate,
            span: .init(latitudeDelta: viewport.latitudeSpan, longitudeDelta: viewport.longitudeSpan)
        )
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let visible = viewport.padded(by: 0.05)
        return response.mapItems.compactMap { item -> ParkingOption? in
            let coordinate = Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
            guard visible.contains(coordinate) else { return nil }
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
                walkingMetres: ParkingRepository.distance(from: coordinate, to: viewport.center), prediction: nil, isBestBet: false, zoneNumber: nil,
                classification: .staticOnly, warningText: "Location only · availability is not live",
                sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: [], clusterCount: nil, clusterViewport: nil
            )
        }.prefix(12).map { $0 }
    }
}

struct FixtureOffStreetParkingService: OffStreetParkingProviding {
    var includeResult = true

    func options(in viewport: ParkingViewport) async -> [ParkingOption] {
        guard includeResult else { return [] }
        let destination = viewport.center
        let coordinate = Coordinate(latitude: destination.latitude + 0.0028, longitude: destination.longitude - 0.001)
        let url = URL(string: "https://www.wilsonparking.com.au")!
        return [.init(
            id: "facility-wilson", kind: .offStreet, title: "Wilson Parking",
            locationLabel: "180 Russell Street, Melbourne", coordinate: coordinate, availabilityState: .unknown,
            available: nil, total: nil, restrictionLabel: "Facility terms apply", restrictionWindow: "Open now · verify with provider", activeNow: true,
            price: .init(primaryText: "Check current price", detail: "Dynamic facility pricing", provider: "Wilson Parking", actionLabel: "Check price / Book with provider", actionURL: url),
            provider: "Wilson Parking", sourceTimestamp: nil, walkingMetres: 420, prediction: nil, isBestBet: false, zoneNumber: nil,
            classification: .staticOnly, warningText: "Location only · availability is not live",
            sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: [], clusterCount: nil, clusterViewport: nil
        )]
    }
}

@preconcurrency import CoreLocation
import Foundation

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestCoordinate() async -> Coordinate?
}

@MainActor
final class LocationService: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestCoordinate() async -> Coordinate? {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation?.resume(returning: nil)
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { manager.requestLocation() }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted:
            continuation?.resume(returning: nil)
            continuation = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        continuation?.resume(returning: coordinate.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) })
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

@MainActor
final class FixtureLocationService: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus
    init(denied: Bool) { authorizationStatus = denied ? .denied : .authorizedWhenInUse }
    func requestCoordinate() async -> Coordinate? { authorizationStatus == .denied ? nil : .melbourneCBD }
}

@preconcurrency import MapKit

enum ParkingNavigationHandoffResult: Equatable {
    case opened
    case intercepted
    case failed
}

@MainActor
protocol ParkingNavigating: AnyObject {
    func navigate(to zone: ParkingZone) -> ParkingNavigationHandoffResult
    func navigate(to option: ParkingOption) -> ParkingNavigationHandoffResult
    func returnToParking(_ session: ParkingSession) -> ParkingNavigationHandoffResult
}

@MainActor
final class AppleMapsNavigator: ParkingNavigating {
    private let intercept: Bool
    init(intercept: Bool = false) { self.intercept = intercept }

    func navigate(to zone: ParkingZone) -> ParkingNavigationHandoffResult {
        open(coordinate: zone.coordinate, name: zone.metadata.streetName, mode: MKLaunchOptionsDirectionsModeDriving)
    }

    func navigate(to option: ParkingOption) -> ParkingNavigationHandoffResult {
        open(coordinate: option.coordinate, name: option.title, mode: MKLaunchOptionsDirectionsModeDriving)
    }

    func returnToParking(_ session: ParkingSession) -> ParkingNavigationHandoffResult {
        open(coordinate: session.coordinate, name: session.parkingTitle, mode: MKLaunchOptionsDirectionsModeWalking)
    }

    private func open(coordinate: Coordinate, name: String, mode: String) -> ParkingNavigationHandoffResult {
        if intercept { return .intercepted }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        let opened = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
        return opened ? .opened : .failed
    }
}

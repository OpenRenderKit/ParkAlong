@preconcurrency import MapKit

@MainActor
protocol ParkingNavigating: AnyObject {
    func navigate(to zone: ParkingZone) -> Bool
    func navigate(to option: ParkingOption) -> Bool
}

@MainActor
final class AppleMapsNavigator: ParkingNavigating {
    private let intercept: Bool
    init(intercept: Bool = false) { self.intercept = intercept }

    func navigate(to zone: ParkingZone) -> Bool {
        open(coordinate: zone.coordinate, name: zone.metadata.streetName)
    }

    func navigate(to option: ParkingOption) -> Bool {
        open(coordinate: option.coordinate, name: option.title)
    }

    private func open(coordinate: Coordinate, name: String) -> Bool {
        if intercept { return true }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        return false
    }
}

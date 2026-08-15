import SwiftUI

@main
struct ParkingAvailabilityApp: App {
    @State private var viewModel = AppEnvironment.makeViewModel()

    var body: some Scene {
        WindowGroup {
            ParkingMapView(viewModel: viewModel)
        }
    }
}

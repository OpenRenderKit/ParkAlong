import SwiftUI

@main
struct ParkAlongApp: App {
    @State private var viewModel = AppEnvironment.makeViewModel()

    var body: some Scene {
        WindowGroup {
            ParkingMapView(viewModel: viewModel)
        }
    }
}

import MapKit
import SwiftUI

struct ParkingMapView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.region(for: .melbourneCBD))
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            map
                .toolbar {
                    MapToolbarContent(viewModel: viewModel, showingAbout: $showingAbout)
                }
                .adaptiveNavigationBarBackground()
                .navigationBarTitleDisplayMode(.inline)
        }
        .adaptiveStatusBarColorScheme()
        .sheet(isPresented: $viewModel.isSearching) {
            DestinationSearchView(viewModel: viewModel)
        }
        .sheet(isPresented: zoneSheetPresented) {
            ZoneDetailView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showingAbout) {
            AboutParkingView()
                .presentationDetents([.medium, .large])
        }
        .task {
            await viewModel.start()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(120))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await viewModel.refresh(force: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refresh(force: true) }
        }
        .onChange(of: viewModel.destination) { _, destination in
            moveCamera(to: destination.coordinate, animated: !reduceMotion)
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if viewModel.destination.id != "current" {
                Annotation(viewModel.destination.name, coordinate: viewModel.destination.coordinate.locationCoordinate, anchor: .center) {
                    DestinationMarker()
                }
            }

            if viewModel.selectedZone != nil {
                ForEach(Array(viewModel.vacantBays.enumerated()), id: \.offset) { _, bay in
                    Annotation("Vacant bay", coordinate: bay.locationCoordinate, anchor: .center) {
                        VacantBayMarker()
                    }
                }
            }

            ForEach(viewModel.staticOptions) { option in
                Annotation("", coordinate: option.coordinate.locationCoordinate, anchor: .bottom) {
                    ParkingPinButton(
                        option: option,
                        isSelected: viewModel.selectedOption?.id == option.id,
                        identifier: "static-pin-\(option.id)"
                    ) {
                        viewModel.selectStatic(option)
                    }
                }
            }

            ForEach(viewModel.offStreetOptions) { option in
                Annotation("", coordinate: option.coordinate.locationCoordinate, anchor: .bottom) {
                    ParkingPinButton(
                        option: option,
                        isSelected: viewModel.selectedOption?.id == option.id,
                        identifier: "offstreet-pin-\(option.id)"
                    ) {
                        viewModel.selectOffStreet(option)
                    }
                }
            }

            ForEach(viewModel.mapZones) { zone in
                let option = ParkingOption.onStreet(zone, duration: viewModel.duration)
                Annotation("", coordinate: zone.coordinate.locationCoordinate, anchor: .bottom) {
                    ParkingPinButton(
                        option: option,
                        isSelected: viewModel.selectedZone?.zoneNumber == zone.zoneNumber,
                        identifier: "zone-pin-\(zone.zoneNumber)",
                        hint: "Shows zone details"
                    ) {
                        Task { await viewModel.selectZone(zone) }
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            MapBottomChrome(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .safeAreaPadding(.bottom)
        }
    }

    private var zoneSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.selectedOption != nil },
            set: { presented in
                if !presented { viewModel.dismissZone() }
            }
        )
    }

    private func moveCamera(to coordinate: Coordinate, animated: Bool) {
        let region = Self.region(for: coordinate)
        if animated {
            withAnimation(.smooth(duration: 0.55)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private static func region(for coordinate: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate.locationCoordinate, latitudinalMeters: 950, longitudinalMeters: 950)
    }
}

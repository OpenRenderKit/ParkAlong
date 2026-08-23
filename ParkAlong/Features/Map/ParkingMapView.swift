import MapKit
import SwiftUI

struct ParkingMapView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.region(for: .melbourneCBD))
    @State private var showingAbout = false

    var body: some View {
        map
            .adaptiveStatusBarColorScheme()
            .sheet(isPresented: $viewModel.isSearching) {
                DestinationSearchView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
            }
            .sheet(isPresented: zoneSheetPresented) {
                ZoneDetailView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(isPresented: $showingAbout) {
                AboutParkingView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
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
            .onChange(of: CameraIntent(destination: viewModel.destination, focus: viewModel.mapFocusRequest)) { oldIntent, newIntent in
                applyCameraIntent(from: oldIntent, to: newIntent)
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
                let option = ParkingOption.onStreet(zone, plan: viewModel.plan)
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
        .onMapCameraChange(frequency: .onEnd) { context in
            // Report the settled visible region, including after a user pan/zoom.
            applyVisibleRegion(context.region)
        }
        .overlay(alignment: .top) {
            MapTopChrome(viewModel: viewModel, showingAbout: $showingAbout)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .safeAreaPadding(.top)
        }
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

    private func applyCameraIntent(from old: CameraIntent, to new: CameraIntent) {
        if let focus = new.focus {
            moveCamera(to: focus, animated: !reduceMotion)
            viewModel.clearMapFocusRequest()
            return
        }
        guard old.focus == nil, old.destination != new.destination else { return }
        moveCamera(to: new.destination.coordinate, animated: !reduceMotion)
    }

    private func applyVisibleRegion(_ region: MKCoordinateRegion) {
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        guard south < north, west < east else { return }
        let viewport = ParkingViewport(
            south: south,
            west: west,
            north: north,
            east: east,
            zoomLevel: Self.zoomLevel(longitudeSpan: region.span.longitudeDelta)
        )
        viewModel.updateViewport(viewport, interactionEnded: true)
    }

    private func moveCamera(to coordinate: Coordinate, animated: Bool) {
        moveCamera(to: Self.region(for: coordinate), animated: animated)
    }

    private func moveCamera(to viewport: ParkingViewport, animated: Bool) {
        let region = MKCoordinateRegion(
            center: viewport.center.locationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(viewport.latitudeSpan, 0.002),
                longitudeDelta: max(viewport.longitudeSpan, 0.002)
            )
        )
        moveCamera(to: region, animated: animated)
    }

    private func moveCamera(to region: MKCoordinateRegion, animated: Bool) {
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

    private static func zoomLevel(longitudeSpan: Double) -> Double {
        log2(360 / max(longitudeSpan, 0.000001))
    }
}

private struct CameraIntent: Equatable {
    let destination: ParkingDestination
    let focus: ParkingViewport?
}

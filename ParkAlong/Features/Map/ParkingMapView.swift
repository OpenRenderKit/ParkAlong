import MapKit
import SwiftUI

struct ParkingMapView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedMarkerID: String?
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
            .onDisappear {
                viewModel.cancelOutstandingWork()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await viewModel.refreshAfterActivation() }
            }
            .onChange(of: CameraIntent(destination: viewModel.destination, focus: viewModel.mapFocusRequest)) { oldIntent, newIntent in
                applyCameraIntent(from: oldIntent, to: newIntent)
            }
            .onChange(of: selectedMarkerID) { _, markerID in
                guard let markerID,
                      let option = viewModel.mapOptions.first(where: { $0.id == markerID }) else { return }
                viewModel.selectMapOption(option)
            }
            .onChange(of: viewModel.selectedOption?.id) { _, optionID in
                selectedMarkerID = optionID
            }
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedMarkerID) {
            UserAnnotation()

            if viewModel.destination.id != "current", viewModel.destination.id != "locating" {
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

            ForEach(renderedMapOptions) { option in
                Annotation("", coordinate: option.coordinate.locationCoordinate, anchor: .bottom) {
                    AvailabilityPin(option: option, isSelected: viewModel.selectedOption?.id == option.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ParkingPinPresentation(option: option).accessibilityLabel)
                        .accessibilityHint(option.clusterCount == nil ? "Shows parking details" : "Zooms into this area")
                        .accessibilityIdentifier(markerIdentifier(for: option))
                }
                .tag(option.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .accessibilityIdentifier("parking-map")
        .accessibilityValue(String(format: "%.2f", viewModel.viewport.zoomLevel))
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { context in
            // Report the settled visible region, including after a user pan/zoom.
            applyVisibleRegion(context.region, userInitiated: cameraPosition.positionedByUser)
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
                if !presented {
                    selectedMarkerID = nil
                    viewModel.dismissZone()
                }
            }
        )
    }

    private func markerIdentifier(for option: ParkingOption) -> String {
        if let zoneNumber = option.zoneNumber { return "zone-pin-\(zoneNumber)" }
        if viewModel.staticOptions.contains(where: { $0.id == option.id }) { return "static-pin-\(option.id)" }
        return "offstreet-pin-\(option.id)"
    }

    /// Lower-value warnings are painted first so useful or selected results remain legible on top.
    private var renderedMapOptions: [ParkingOption] {
        viewModel.mapOptions.sorted { lhs, rhs in
            let lhsPriority = renderPriority(for: lhs)
            let rhsPriority = renderPriority(for: rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.id < rhs.id
        }
    }

    private func renderPriority(for option: ParkingOption) -> Int {
        if option.id == viewModel.selectedOption?.id { return 4 }
        if option.classification == .verifiedLive { return 3 }
        if option.classification == .predicted { return 2 }
        if option.clusterCount != nil { return 1 }
        return 0
    }

    private func applyCameraIntent(from old: CameraIntent, to new: CameraIntent) {
        // `map-area` records that the person took control during startup; it is
        // descriptive state, not a request to move the camera again.
        guard new.destination.id != "map-area" else { return }
        if let focus = new.focus {
            moveCamera(to: focus, animated: !reduceMotion)
            viewModel.clearMapFocusRequest()
            return
        }
        guard old.focus == nil, old.destination != new.destination else { return }
        moveCamera(to: new.destination.coordinate, animated: !reduceMotion)
    }

    private func applyVisibleRegion(_ region: MKCoordinateRegion, userInitiated: Bool) {
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
        viewModel.updateViewport(
            viewport,
            interactionEnded: true,
            userInitiated: userInitiated
        )
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

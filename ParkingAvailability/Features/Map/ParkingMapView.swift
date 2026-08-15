import MapKit
import SwiftUI

struct ParkingMapView: View {
    @Bindable var viewModel: ParkingMapViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .region(Self.region(for: .melbourneCBD))
    @State private var showingAbout = false

    var body: some View {
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

            ForEach(viewModel.mapZones) { zone in
                Annotation("", coordinate: zone.coordinate.locationCoordinate, anchor: .bottom) {
                    Button {
                        Task { await viewModel.selectZone(zone) }
                    } label: {
                        AvailabilityPin(
                            zone: zone,
                            isSelected: viewModel.selectedZone?.zoneNumber == zone.zoneNumber
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(AvailabilityStyle.accessibilityLabel(for: zone))
                    .accessibilityHint("Shows zone details")
                    .accessibilityIdentifier("zone-pin-\(zone.zoneNumber)")
                }
            }

            ForEach(viewModel.offStreetOptions) { option in
                Annotation(option.title, coordinate: option.coordinate.locationCoordinate, anchor: .bottom) {
                    Button { viewModel.selectOffStreet(option) } label: { OffStreetPin() }
                        .buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("\(option.title), off-street parking, check provider for spaces and price")
                        .accessibilityIdentifier("offstreet-pin-\(option.id)")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            MapSearchBar(viewModel: viewModel, showingAbout: $showingAbout)
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

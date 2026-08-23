import Foundation
import Observation

enum AvailabilityLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@Observable
@MainActor
final class ParkingMapViewModel {
    private let repository: any ParkingRepositoryProviding
    private let locationService: any LocationProviding
    private let destinationSearch: any DestinationSearching
    private let navigator: any ParkingNavigating
    private let offStreetService: any OffStreetParkingProviding
    private let staticParkingService: any StaticParkingProviding
    private var refreshGeneration = 0

    var destination = ParkingDestination(id: "cbd", name: "Melbourne CBD", subtitle: "Central Melbourne", coordinate: .melbourneCBD)
    var duration: StayDuration = .oneHour
    var zones: [ParkingZone] = []
    var selectedZone: ParkingZone?
    var selectedOffStreetOption: ParkingOption?
    var offStreetOptions: [ParkingOption] = []
    var staticOptions: [ParkingOption] = []
    var vacantBays: [Coordinate] = []
    var state: AvailabilityLoadState = .idle
    var mode: ParkingDataMode = .live
    var notice = ""
    var checkedAt: Date?
    var searchResults: [ParkingDestination] = []
    var isSearching = false
    var navigationWasIntercepted = false

    /// Keeps the map legible while retaining the highest-ranked availability-first options.
    var mapZones: [ParkingZone] { Array(zones.prefix(24)) }

    var selectedOption: ParkingOption? {
        if let selectedZone { return .onStreet(selectedZone, duration: duration) }
        return selectedOffStreetOption
    }

    init(repository: any ParkingRepositoryProviding, locationService: any LocationProviding, destinationSearch: any DestinationSearching, navigator: any ParkingNavigating, offStreetService: any OffStreetParkingProviding, staticParkingService: any StaticParkingProviding) {
        self.repository = repository
        self.locationService = locationService
        self.destinationSearch = destinationSearch
        self.navigator = navigator
        self.offStreetService = offStreetService
        self.staticParkingService = staticParkingService
    }

    func start() async { await refresh(force: false) }

    func refresh(force: Bool = true) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        state = .loading
        async let nearbyFacilities = offStreetService.options(near: destination.coordinate)
        async let mappedParking = staticParkingService.options(near: destination.coordinate, duration: duration, at: Date.now)
        do {
            let result = try await repository.refresh(destination: destination.coordinate, duration: duration, now: .now, force: force)
            guard generation == refreshGeneration else { return }
            zones = result.zones
            mode = result.mode
            notice = result.notice
            checkedAt = result.checkedAt
            if let selected = selectedZone { selectedZone = zones.first(where: { $0.zoneNumber == selected.zoneNumber }) }
            state = .loaded
            let facilities = await nearbyFacilities
            let staticLocations = await mappedParking
            guard generation == refreshGeneration else { return }
            offStreetOptions = facilities
            staticOptions = staticLocations
        } catch {
            guard generation == refreshGeneration else { return }
            let facilities = await nearbyFacilities
            let staticLocations = await mappedParking
            guard generation == refreshGeneration else { return }
            offStreetOptions = facilities
            staticOptions = staticLocations
            if zones.isEmpty && facilities.isEmpty && staticLocations.isEmpty {
                state = .failed("Parking information couldn’t be updated. Try again in a moment.")
            } else {
                state = .loaded
                notice = zones.isEmpty
                    ? "Live availability unavailable · showing mapped parking with warnings"
                    : "Couldn’t refresh · showing the last checked results"
            }
        }
    }

    func updateDuration(_ value: StayDuration) async {
        guard prepareDurationUpdate(value) else { return }
        await refresh(force: true)
    }

    /// Applies the visible selection immediately, then refreshes parking in the background.
    func selectDuration(_ value: StayDuration) {
        guard prepareDurationUpdate(value) else { return }
        Task { await refresh(force: true) }
    }

    private func prepareDurationUpdate(_ value: StayDuration) -> Bool {
        guard duration != value else { return false }
        duration = value
        refreshGeneration += 1
        selectedZone = nil
        selectedOffStreetOption = nil
        zones = []
        staticOptions = []
        vacantBays = []
        notice = "Finding parking for a \(value.selectionDescription) stay"
        return true
    }

    func useCurrentLocation() async {
        guard let coordinate = await locationService.requestCoordinate() else {
            destination = .init(id: "cbd", name: "Melbourne CBD", subtitle: "Location unavailable", coordinate: .melbourneCBD)
            await refresh(force: false)
            return
        }
        destination = .init(id: "current", name: "Current location", subtitle: "Near you", coordinate: coordinate)
        await refresh(force: true)
    }

    func search(query: String) async {
        do {
            let results = try await destinationSearch.search(query)
            guard !Task.isCancelled else { return }
            searchResults = results
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
        }
    }

    func chooseDestination(_ value: ParkingDestination) async {
        destination = value
        isSearching = false
        searchResults = []
        selectedZone = nil
        selectedOffStreetOption = nil
        vacantBays = []
        await refresh(force: true)
    }

    func selectZone(_ zone: ParkingZone) async {
        selectedOffStreetOption = nil
        selectedZone = zone
        vacantBays = (try? await repository.vacantBays(zoneNumber: zone.zoneNumber, now: .now)) ?? []
    }

    func selectOffStreet(_ option: ParkingOption) {
        selectedZone = nil
        vacantBays = []
        selectedOffStreetOption = option
    }

    func selectStatic(_ option: ParkingOption) {
        selectOffStreet(option)
    }

    func dismissZone() {
        selectedZone = nil
        selectedOffStreetOption = nil
        vacantBays = []
        navigationWasIntercepted = false
    }

    func navigate() {
        if let selectedZone {
            navigationWasIntercepted = navigator.navigate(to: selectedZone)
        } else if let selectedOffStreetOption {
            navigationWasIntercepted = navigator.navigate(to: selectedOffStreetOption)
        }
    }
}

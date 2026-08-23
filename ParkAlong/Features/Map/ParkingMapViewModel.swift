import Foundation
import Observation

enum AvailabilityLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum ParkingSearchState: Equatable {
    case idle
    case loading
    case loaded
    case empty
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
    private var searchGeneration = 0
    private var searchParkingOptions: [String: ParkingOption] = [:]
    @ObservationIgnored private var viewportRefreshTask: Task<Void, Never>?

    var destination = ParkingDestination(id: "cbd", name: "Melbourne CBD", subtitle: "Central Melbourne", coordinate: .melbourneCBD)
    var plan = ParkingPlan(arrival: .now, duration: .oneHour)
    var duration: StayDuration { StayDuration(rawValue: plan.durationMinutes) ?? .eightHours }
    var viewport = ParkingMapViewModel.viewport(centeredAt: .melbourneCBD)
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
    var searchState: ParkingSearchState = .idle
    var isSearching = false
    var navigationWasIntercepted = false
    var mapFocusRequest: ParkingViewport?

    /// Keeps the map legible while retaining the highest-ranked availability-first options.
    var mapZones: [ParkingZone] { Array(zones.prefix(24)) }

    var selectedOption: ParkingOption? {
        if let selectedZone { return .onStreet(selectedZone, plan: plan) }
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
        let plan = self.plan
        let now = Date.now
        let viewport = self.viewport
        async let nearbyFacilities = offStreetService.options(in: viewport)
        async let mappedParking = staticParkingService.options(in: viewport, plan: plan)
        do {
            let result = try await repository.refresh(viewport: viewport, plan: plan, now: now, force: force)
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
        guard preparePlanUpdate(ParkingPlan(arrival: plan.arrival, duration: value, isPublicHoliday: plan.isPublicHoliday)) else { return }
        await refresh(force: true)
    }

    /// Applies the visible selection immediately, then refreshes parking in the background.
    func selectDuration(_ value: StayDuration) {
        guard preparePlanUpdate(ParkingPlan(arrival: plan.arrival, duration: value, isPublicHoliday: plan.isPublicHoliday)) else { return }
        Task { await refresh(force: true) }
    }

    func applyPlan(_ value: ParkingPlan) {
        guard preparePlanUpdate(value) else { return }
        Task { await refresh(force: true) }
    }

    private func preparePlanUpdate(_ value: ParkingPlan) -> Bool {
        guard plan != value else { return false }
        plan = value
        refreshGeneration += 1
        selectedZone = nil
        selectedOffStreetOption = nil
        notice = "Finding parking for a \(value.selectionDescription) stay"
        return true
    }

    func updateViewport(_ value: ParkingViewport, interactionEnded: Bool) {
        let changed = value.materiallyDiffers(from: viewport)
        viewport = value
        guard interactionEnded, changed else { return }
        viewportRefreshTask?.cancel()
        viewportRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.refresh(force: false)
        }
    }

    func useCurrentLocation() async {
        guard let coordinate = await locationService.requestCoordinate() else {
            destination = .init(id: "cbd", name: "Melbourne CBD", subtitle: "Location unavailable", coordinate: .melbourneCBD)
            viewport = Self.viewport(centeredAt: .melbourneCBD)
            mapFocusRequest = viewport
            await refresh(force: false)
            return
        }
        destination = .init(id: "current", name: "Current location", subtitle: "Near you", coordinate: coordinate)
        viewport = Self.viewport(centeredAt: coordinate)
        mapFocusRequest = viewport
        await refresh(force: true)
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchGeneration += 1
            searchResults = []
            searchParkingOptions = [:]
            searchState = .idle
            return
        }
        searchGeneration += 1
        let generation = searchGeneration
        searchState = .loading
        async let parkingMatches = staticParkingService.search(trimmed, near: viewport, plan: plan, limit: 20)
        do {
            let places = try await destinationSearch.search(trimmed, in: viewport)
            let parking = await parkingMatches
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchParkingOptions = Dictionary(uniqueKeysWithValues: parking.map { ($0.id, $0) })
            let parkingDestinations = parking.map { option in
                ParkingDestination(
                    id: "parking-\(option.id)", name: option.title,
                    subtitle: "\(option.kind.rawValue) · \(option.price.primaryText) · \(option.locationLabel)",
                    coordinate: option.coordinate, kind: .parking, parkingOptionID: option.id
                )
            }
            searchResults = DestinationSearchRanker.rank(places + parkingDestinations, query: trimmed, viewport: viewport)
            searchState = searchResults.isEmpty ? .empty : .loaded
        } catch {
            let parking = await parkingMatches
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchParkingOptions = Dictionary(uniqueKeysWithValues: parking.map { ($0.id, $0) })
            if parking.isEmpty {
                searchState = .failed("Place search is unavailable. Check your connection and try again.")
            } else {
                searchResults = parking.map { option in
                    ParkingDestination(
                        id: "parking-\(option.id)", name: option.title,
                        subtitle: "\(option.kind.rawValue) · \(option.price.primaryText) · \(option.locationLabel)",
                        coordinate: option.coordinate, kind: .parking, parkingOptionID: option.id
                    )
                }
                searchState = .loaded
            }
        }
    }

    func chooseDestination(_ value: ParkingDestination) async {
        if let optionID = value.parkingOptionID, let option = searchParkingOptions[optionID] {
            isSearching = false
            searchResults = []
            searchState = .idle
            selectStatic(option)
            return
        }
        destination = value
        viewport = Self.viewport(centeredAt: value.coordinate)
        mapFocusRequest = viewport
        isSearching = false
        searchResults = []
        searchState = .idle
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
        if let target = option.clusterViewport {
            selectedZone = nil
            selectedOffStreetOption = nil
            vacantBays = []
            viewport = target
            mapFocusRequest = target
            Task { await refresh(force: false) }
            return
        }
        selectOffStreet(option)
    }

    func clearMapFocusRequest() {
        mapFocusRequest = nil
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

    private static func viewport(centeredAt coordinate: Coordinate) -> ParkingViewport {
        let halfSpanMetres = 475.0
        let latitudeHalfSpan = halfSpanMetres / 111_320
        let latitudeRadians = coordinate.latitude * .pi / 180
        let metresPerLongitudeDegree = max(1, 111_320 * cos(latitudeRadians))
        let longitudeHalfSpan = halfSpanMetres / metresPerLongitudeDegree
        let longitudeSpan = longitudeHalfSpan * 2
        return ParkingViewport(
            south: coordinate.latitude - latitudeHalfSpan,
            west: coordinate.longitude - longitudeHalfSpan,
            north: coordinate.latitude + latitudeHalfSpan,
            east: coordinate.longitude + longitudeHalfSpan,
            zoomLevel: log2(360 / longitudeSpan)
        )
    }
}

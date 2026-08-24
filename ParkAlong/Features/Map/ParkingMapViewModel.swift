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
    private static let viewportQueryPaddingFraction = 0.5
    private let repository: any ParkingRepositoryProviding
    private let locationService: any LocationProviding
    private let destinationSearch: any DestinationSearching
    private let navigator: any ParkingNavigating
    private let offStreetService: any OffStreetParkingProviding
    private let staticParkingService: any StaticParkingProviding
    private let viewportDebounce: Duration
    private var refreshGeneration = 0
    private var searchGeneration = 0
    private var locationRequestGeneration = 0
    private var searchParkingOptions: [String: ParkingOption] = [:]
    private var hasStarted = false
    @ObservationIgnored private var viewportRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var locationRequestTask: Task<LocationRequestResult, Never>?

    var destination = ParkingDestination(
        id: "locating",
        name: "Current location",
        subtitle: "Locating…",
        coordinate: .melbourneCBD
    )
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
    var isLocating: Bool { destination.id == "locating" }

    /// Keeps useful live/predicted results ahead of location-only warnings and protects map gestures.
    var mapOptions: [ParkingOption] {
        var options = zones.prefix(24).map { ParkingOption.onStreet($0, plan: plan) }
        options.append(contentsOf: offStreetOptions)
        options.append(contentsOf: staticOptions)
        if let selectedOption, !options.contains(where: { $0.id == selectedOption.id }) {
            options.append(selectedOption)
        }
        return ParkingMarkerSelector.select(
            options: options,
            selectedID: selectedOption?.id,
            viewport: viewport
        )
    }

    var mapZones: [ParkingZone] {
        let visibleIDs = Set(mapOptions.compactMap(\.zoneNumber))
        return zones.filter { visibleIDs.contains($0.zoneNumber) }
    }

    var selectedOption: ParkingOption? {
        if let selectedZone { return .onStreet(selectedZone, plan: plan) }
        return selectedOffStreetOption
    }

    init(
        repository: any ParkingRepositoryProviding,
        locationService: any LocationProviding,
        destinationSearch: any DestinationSearching,
        navigator: any ParkingNavigating,
        offStreetService: any OffStreetParkingProviding,
        staticParkingService: any StaticParkingProviding,
        viewportDebounce: Duration = .milliseconds(250)
    ) {
        self.repository = repository
        self.locationService = locationService
        self.destinationSearch = destinationSearch
        self.navigator = navigator
        self.offStreetService = offStreetService
        self.staticParkingService = staticParkingService
        self.viewportDebounce = viewportDebounce
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await useCurrentLocation()
    }

    func refresh(force: Bool = true) async {
        activeRefreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let plan = self.plan
        let now = Date.now
        let viewport = self.viewport.padded(by: Self.viewportQueryPaddingFraction)
        state = .loading
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(
                generation: generation,
                viewport: viewport,
                plan: plan,
                now: now,
                force: force
            )
        }
        activeRefreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if generation == refreshGeneration { activeRefreshTask = nil }
    }

    private func performRefresh(
        generation: Int,
        viewport: ParkingViewport,
        plan: ParkingPlan,
        now: Date,
        force: Bool
    ) async {
        async let nearbyFacilities = offStreetService.options(in: viewport)
        async let mappedParking = staticParkingService.options(in: viewport, plan: plan)
        do {
            let result = try await repository.refresh(viewport: viewport, plan: plan, now: now, force: force)
            let facilities = await nearbyFacilities
            let staticLocations = await mappedParking
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            zones = result.zones
            offStreetOptions = facilities
            staticOptions = staticLocations
            mode = result.mode
            notice = result.notice
            checkedAt = result.checkedAt
            if let selected = selectedZone { selectedZone = zones.first(where: { $0.zoneNumber == selected.zoneNumber }) }
            rebindSelectedOption(facilities: facilities, staticLocations: staticLocations)
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            let facilities = await nearbyFacilities
            let staticLocations = await mappedParking
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            offStreetOptions = facilities
            staticOptions = staticLocations
            rebindSelectedOption(facilities: facilities, staticLocations: staticLocations)
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

    func refreshAfterActivation() async {
        guard !isLocating else { return }
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
        activeRefreshTask?.cancel()
        viewportRefreshTask?.cancel()
        refreshGeneration += 1
        selectedZone = nil
        selectedOffStreetOption = nil
        notice = "Finding parking for a \(value.selectionDescription) stay"
        return true
    }

    func updateViewport(
        _ value: ParkingViewport,
        interactionEnded: Bool,
        userInitiated: Bool = true
    ) {
        if userInitiated { noteMapInteraction(at: value.center) }
        // MapKit reports an automatic camera settle while Core Location is
        // pending. It is not a real viewport choice and should not kick off a
        // statewide/default-area refresh.
        guard destination.id != "locating" else { return }
        let changed = value.materiallyDiffers(from: viewport)
        viewport = value
        guard interactionEnded, changed else { return }
        viewportRefreshTask?.cancel()
        activeRefreshTask?.cancel()
        refreshGeneration += 1
        viewportRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.viewportDebounce ?? .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.refresh(force: false)
        }
    }

    /// A deliberate pan or pinch takes ownership of the camera. A late startup
    /// location fix must never pull the map away from where the person moved it.
    private func noteMapInteraction(at coordinate: Coordinate) {
        guard destination.id == "locating" else { return }
        invalidatePendingLocationRequest()
        destination = .init(
            id: "map-area",
            name: "Map area",
            subtitle: "Using the area you chose",
            coordinate: coordinate
        )
    }

    func useCurrentLocation() async {
        locationRequestTask?.cancel()
        locationRequestGeneration += 1
        let generation = locationRequestGeneration
        destination = .init(
            id: "locating",
            name: "Current location",
            subtitle: "Locating…",
            coordinate: destination.coordinate
        )

        let requestTask = Task { await locationService.requestCoordinate() }
        locationRequestTask = requestTask
        let result = await withTaskCancellationHandler {
            await requestTask.value
        } onCancel: {
            requestTask.cancel()
        }
        guard !Task.isCancelled, generation == locationRequestGeneration else { return }
        locationRequestTask = nil

        switch result {
        case let .success(coordinate):
            destination = .init(id: "current", name: "Current location", subtitle: "Near you", coordinate: coordinate)
            viewport = Self.viewport(centeredAt: coordinate)
            mapFocusRequest = viewport
            await refresh(force: true)
        case .denied:
            await applyLocationFallback(
                subtitle: "Location permission denied",
                notice: "Location permission denied · showing Melbourne CBD"
            )
        case .restricted:
            await applyLocationFallback(
                subtitle: "Location access restricted",
                notice: "Location access restricted · showing Melbourne CBD"
            )
        case .timedOut:
            await applyLocationFallback(
                subtitle: "Current location timed out",
                notice: "Location timed out · showing Melbourne CBD"
            )
        case .unavailable:
            await applyLocationFallback(
                subtitle: "Current location unavailable",
                notice: "Location unavailable · showing Melbourne CBD"
            )
        case .cancelled:
            return
        }
    }

    private func applyLocationFallback(subtitle: String, notice fallbackNotice: String) async {
        destination = .init(id: "cbd", name: "Melbourne CBD", subtitle: subtitle, coordinate: .melbourneCBD)
        viewport = Self.viewport(centeredAt: .melbourneCBD)
        mapFocusRequest = viewport
        await refresh(force: false)
        notice = fallbackNotice
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
        invalidatePendingLocationRequest()
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

    func selectMapOption(_ option: ParkingOption) {
        if let zoneNumber = option.zoneNumber,
           let zone = zones.first(where: { $0.zoneNumber == zoneNumber }) {
            Task { await selectZone(zone) }
        } else if staticOptions.contains(where: { $0.id == option.id }) || option.clusterCount != nil {
            selectStatic(option)
        } else {
            selectOffStreet(option)
        }
    }

    func clearMapFocusRequest() {
        mapFocusRequest = nil
    }

    func cancelOutstandingWork() {
        let cancelledStartup = destination.id == "locating" && locationRequestTask != nil
        invalidatePendingLocationRequest()
        if cancelledStartup { hasStarted = false }
        viewportRefreshTask?.cancel()
        viewportRefreshTask = nil
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
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

    private func invalidatePendingLocationRequest() {
        guard locationRequestTask != nil else { return }
        locationRequestGeneration += 1
        locationRequestTask?.cancel()
        locationRequestTask = nil
    }

    private func rebindSelectedOption(
        facilities: [ParkingOption],
        staticLocations: [ParkingOption]
    ) {
        guard let selected = selectedOffStreetOption,
              let updated = (facilities + staticLocations).first(where: { $0.id == selected.id }) else { return }
        selectedOffStreetOption = updated
    }
}

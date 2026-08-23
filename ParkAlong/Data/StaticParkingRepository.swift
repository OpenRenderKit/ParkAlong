import Foundation

struct StaticParkingCacheMetrics: Equatable, Sendable {
    let hits: Int
    let misses: Int
    let entries: Int
}

actor StaticParkingRepository: StaticParkingProviding {
    private var locations: [StaticParkingLocation]
    private var spatialIndex: StaticParkingSpatialIndex?
    private var searchEntries: [SearchEntry]
    private var loader: (@Sendable () throws -> [StaticParkingLocation])?
    private var didAttemptLoad: Bool
    private let resultLimit: Int
    private let ruleResolver: ParkingRuleResolver
    private let remote: (any RemoteParkingProviding)?
    private let catalogVersion: String
    private var queryCache: [QueryKey: [ParkingOption]] = [:]
    private var queryCacheOrder: [QueryKey] = []
    private var queryCacheHits = 0
    private var queryCacheMisses = 0
    private var resolutionPlanKey: ResolutionPlanKey?
    private var resolutionCache: [String: StaticResolution] = [:]

    init(
        locations: [StaticParkingLocation],
        resultLimit: Int = 160,
        ruleResolver: ParkingRuleResolver = ParkingRuleResolver(),
        remote: (any RemoteParkingProviding)? = nil,
        catalogVersion: String = "bundled-v1"
    ) {
        self.locations = locations
        self.spatialIndex = StaticParkingSpatialIndex(locations: locations)
        self.searchEntries = Self.makeSearchEntries(locations)
        self.loader = nil
        self.didAttemptLoad = true
        self.resultLimit = resultLimit
        self.ruleResolver = ruleResolver
        self.remote = remote
        self.catalogVersion = catalogVersion
    }

    init(
        loader: @escaping @Sendable () throws -> [StaticParkingLocation],
        resultLimit: Int = 160,
        ruleResolver: ParkingRuleResolver = ParkingRuleResolver(),
        remote: (any RemoteParkingProviding)? = nil,
        catalogVersion: String = "bundled-v1"
    ) {
        self.locations = []
        self.spatialIndex = nil
        self.searchEntries = []
        self.loader = loader
        self.didAttemptLoad = false
        self.resultLimit = resultLimit
        self.ruleResolver = ruleResolver
        self.remote = remote
        self.catalogVersion = catalogVersion
    }

    func options(in viewport: ParkingViewport, plan: ParkingPlan) async -> [ParkingOption] {
        guard !Task.isCancelled else { return [] }
        let cacheKey = QueryKey(viewport: viewport, plan: plan)
        if remote == nil, let cached = queryCache[cacheKey] {
            queryCacheHits += 1
            return cached
        }
        queryCacheMisses += 1
        let queryViewport = viewport.padded(by: 0.2)
        let availableLocations = await availableLocations(viewport: queryViewport, plan: plan)
        guard !Task.isCancelled else { return [] }
        prepareResolutionCache(for: plan)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(min(availableLocations.count, resultLimit * 4))
        for (offset, location) in availableLocations.enumerated() {
            if offset.isMultiple(of: 64), Task.isCancelled { return [] }
            guard queryViewport.contains(location.coordinate) else { continue }
            let distance = ParkingRepository.distance(from: location.coordinate, to: viewport.center)
            guard case .eligible(let rule, let prediction) = resolution(
                for: location,
                plan: plan,
                cacheAllowed: remote == nil
            ) else { continue }
            candidates.append(Candidate(location: location, rule: rule, distance: distance, prediction: prediction))
        }
        candidates.sort {
            if $0.isOpenStreetMap != $1.isOpenStreetMap { return !$0.isOpenStreetMap }
            return $0.distance < $1.distance
        }

        let officialIndex = Dictionary(
            grouping: candidates.filter { !$0.isOpenStreetMap },
            by: { SpatialKey(coordinate: $0.location.coordinate) }
        )
        let deduplicated = candidates.filter { candidate in
            !candidate.isOpenStreetMap || !hasNearbyOfficial(candidate.location.coordinate, in: officialIndex)
        }
        let visibleCandidates = viewport.zoomLevel < 13
            ? deduplicated
            : Array(deduplicated.prefix(resultLimit))
        guard !Task.isCancelled else { return [] }
        let options = visibleCandidates.map { makeOption($0, plan: plan) }
        let result = viewport.zoomLevel < 13 ? clustered(options, in: viewport) : options
        if remote == nil { cache(result, for: cacheKey) }
        return result
    }

    func cacheMetrics() -> StaticParkingCacheMetrics {
        StaticParkingCacheMetrics(hits: queryCacheHits, misses: queryCacheMisses, entries: queryCache.count)
    }

    func search(_ query: String, near viewport: ParkingViewport, plan: ParkingPlan, limit: Int = 20) async -> [ParkingOption] {
        let normalized = Self.normalizedSearchText(query)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        guard !tokens.isEmpty else { return [] }
        _ = loadLocationsIfNeeded()
        prepareResolutionCache(for: plan)
        return searchEntries.compactMap { entry -> (Candidate, Double)? in
            if Task.isCancelled { return nil }
            let coverage = Double(tokens.intersection(entry.tokens).count) / Double(tokens.count)
            let exact = entry.normalizedText.contains(normalized) ? 1.0 : 0
            let textScore = max(exact, coverage * 0.8)
            let location = entry.location
            guard textScore >= 0.45,
                  case .eligible(let rule, let prediction) = resolution(for: location, plan: plan) else { return nil }
            let distance = ParkingRepository.distance(from: location.coordinate, to: viewport.center)
            let sourceBoost = location.source.id == "openstreetmap-victoria-parking" ? 0 : 0.08
            let proximity = max(0, 1 - min(distance, 100_000) / 100_000)
            return (Candidate(location: location, rule: rule, distance: distance, prediction: prediction), textScore * 0.8 + proximity * 0.12 + sourceBoost)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(max(1, limit))
        .map { makeOption($0.0, plan: plan) }
    }

    private func availableLocations(viewport: ParkingViewport, plan: ParkingPlan) async -> [StaticParkingLocation] {
        _ = loadLocationsIfNeeded()
        var records = spatialIndex?.locations(in: viewport) ?? locations.filter { viewport.contains($0.coordinate) }
        if let remote {
            let query = RemoteParkingQuery(viewport: viewport, plan: plan, catalogVersion: catalogVersion)
            if let remoteLocations = try? await remote.locations(for: query) {
                records = RemoteParkingMerger.merge(
                    bundled: records,
                    remote: remoteLocations.filter { viewport.contains($0.coordinate) }
                )
            }
        }
        return records
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func loadLocationsIfNeeded() -> [StaticParkingLocation] {
        guard !didAttemptLoad else { return locations }
        didAttemptLoad = true
        defer { loader = nil }
        locations = (try? loader?()) ?? []
        spatialIndex = StaticParkingSpatialIndex(locations: locations)
        searchEntries = Self.makeSearchEntries(locations)
        return locations
    }

    private func prepareResolutionCache(for plan: ParkingPlan) {
        let key = ResolutionPlanKey(plan: plan)
        guard key != resolutionPlanKey else { return }
        resolutionPlanKey = key
        resolutionCache.removeAll(keepingCapacity: true)
        queryCache.removeAll(keepingCapacity: true)
        queryCacheOrder.removeAll(keepingCapacity: true)
    }

    private func resolution(
        for location: StaticParkingLocation,
        plan: ParkingPlan,
        cacheAllowed: Bool = true
    ) -> StaticResolution {
        if cacheAllowed, let cached = resolutionCache[location.id] { return cached }
        let result: StaticResolution
        if let rule = ruleResolver.resolve(location: location, plan: plan), rule.isEligible {
            let prediction = location.predictionEvidence.flatMap {
                PredictionEngine.staticEstimate(
                    capacity: location.capacity,
                    evidence: $0,
                    archetype: location.archetype,
                    context: demandContext(for: location, plan: plan),
                    forecastDate: plan.arrival
                )
            }
            result = .eligible(rule, prediction)
        } else {
            result = .ineligible
        }
        if cacheAllowed { resolutionCache[location.id] = result }
        return result
    }

    private func cache(_ options: [ParkingOption], for key: QueryKey) {
        queryCache[key] = options
        queryCacheOrder.removeAll { $0 == key }
        queryCacheOrder.append(key)
        while queryCacheOrder.count > 16 {
            queryCache.removeValue(forKey: queryCacheOrder.removeFirst())
        }
    }

    private static func makeSearchEntries(_ locations: [StaticParkingLocation]) -> [SearchEntry] {
        locations.map { location in
            let normalized = normalizedSearchText("\(location.name) \(location.municipality) \(location.source.name)")
            return SearchEntry(
                location: location,
                normalizedText: normalized,
                tokens: Set(normalized.split(separator: " ").map(String.init))
            )
        }
    }

    private func makeOption(_ candidate: Candidate, plan: ParkingPlan) -> ParkingOption {
        let location = candidate.location
        let kind: ParkingOptionKind = location.kind == .onStreet ? .onStreet : .offStreet
        let sourceAgeWarning = location.source.datasetUpdatedAt == nil
            ? "Location only · availability is not live"
            : "Static data checked by ParkAlong · availability is not live"
        let classification: ParkingDataClassification = candidate.prediction == nil ? location.classification : .predicted
        let available = candidate.prediction?.expectedAvailable.map { Int($0.rounded(.down)) }
        return ParkingOption(
            id: "static-\(location.id)", kind: kind, title: location.name,
            locationLabel: location.municipality, coordinate: location.coordinate,
            availabilityState: .unknown, available: available, total: location.capacity,
            restrictionLabel: candidate.rule.timeLimitText,
            restrictionWindow: candidate.rule.restrictionWindow,
            activeNow: true, price: candidate.rule.price, provider: location.source.name,
            sourceTimestamp: nil, walkingMetres: candidate.distance, prediction: candidate.prediction,
            isBestBet: false, zoneNumber: nil, classification: classification,
            warningText: candidate.prediction == nil ? sourceAgeWarning : "Prediction based on validated historical evidence · not live",
            sourceDatasetAt: location.source.datasetUpdatedAt,
            sourceCheckedAt: location.source.checkedAt,
            schedule: ruleResolver.weeklySchedule(location: location, plan: plan),
            clusterCount: nil, clusterViewport: nil
        )
    }

    private func clustered(_ options: [ParkingOption], in viewport: ParkingViewport) -> [ParkingOption] {
        guard options.count > 1 else { return options }
        let gridSize = viewport.zoomLevel < 10 ? 8 : (viewport.zoomLevel < 12 ? 12 : 18)
        let latitudeSpan = max(viewport.latitudeSpan, 0.000_001)
        let longitudeSpan = max(viewport.longitudeSpan, 0.000_001)
        let groups = Dictionary(grouping: options) { option in
            let row = Int(((option.coordinate.latitude - viewport.south) / latitudeSpan * Double(gridSize)).rounded(.down))
            let column = Int(((option.coordinate.longitude - viewport.west) / longitudeSpan * Double(gridSize)).rounded(.down))
            return GridKey(row: row, column: column)
        }

        return groups.sorted { lhs, rhs in
            if lhs.key.row != rhs.key.row { return lhs.key.row < rhs.key.row }
            return lhs.key.column < rhs.key.column
        }.map { key, members in
            guard members.count > 1 else { return members[0] }
            let latitudes = members.map(\.coordinate.latitude)
            let longitudes = members.map(\.coordinate.longitude)
            let south = latitudes.min()!
            let north = latitudes.max()!
            let west = longitudes.min()!
            let east = longitudes.max()!
            let latitudePadding = max((north - south) * 0.45, 0.002)
            let longitudePadding = max((east - west) * 0.45, 0.002)
            let target = ParkingViewport(
                south: south - latitudePadding, west: west - longitudePadding,
                north: north + latitudePadding, east: east + longitudePadding,
                zoomLevel: min(16, viewport.zoomLevel + 2)
            )
            let municipalities = Set(members.map(\.locationLabel))
            let coordinate = Coordinate(
                latitude: latitudes.reduce(0, +) / Double(members.count),
                longitude: longitudes.reduce(0, +) / Double(members.count)
            )
            return ParkingOption(
                id: "cluster-\(Int(viewport.zoomLevel))-\(key.row)-\(key.column)", kind: .offStreet,
                title: "\(members.count) parking locations",
                locationLabel: municipalities.count == 1 ? municipalities.first! : "Visible area",
                coordinate: coordinate, availabilityState: .unknown, available: nil, total: nil,
                restrictionLabel: "Zoom in to compare time limits", restrictionWindow: "Grouped for this map view",
                activeNow: true,
                price: .init(primaryText: "Multiple prices", detail: "Zoom in for exact facility and street rates",
                             provider: "ParkAlong", actionLabel: nil, actionURL: nil),
                provider: "ParkAlong", sourceTimestamp: nil,
                walkingMetres: members.map(\.walkingMetres).min() ?? 0, prediction: nil,
                isBestBet: false, zoneNumber: nil, classification: .staticOnly,
                warningText: "Grouped mapped locations · zoom in for source details",
                sourceDatasetAt: nil, sourceCheckedAt: nil, schedule: [],
                clusterCount: members.count, clusterViewport: target
            )
        }
    }

    private func demandContext(for location: StaticParkingLocation, plan: ParkingPlan) -> ParkingDemandContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: plan.arrival)
        return ParkingDemandContext(
            weekday: components.weekday ?? 1,
            minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            isPublicHoliday: plan.isPublicHoliday,
            isSchoolHoliday: false,
            clearWeatherIndex: 0.5,
            eventIntensity: 0,
            trafficIndex: 1,
            hourlyPriceCents: location.tariffs.first?.hourlyCents,
            maxStayMinutes: location.schedules.compactMap(\.maxStayMinutes).min()
        )
    }

    private func hasNearbyOfficial(
        _ coordinate: Coordinate,
        in index: [SpatialKey: [Candidate]]
    ) -> Bool {
        let cell = SpatialKey(coordinate: coordinate)
        for latitudeOffset in -1...1 {
            for longitudeOffset in -1...1 {
                let nearby = SpatialKey(latitude: cell.latitude + latitudeOffset, longitude: cell.longitude + longitudeOffset)
                if index[nearby]?.contains(where: {
                    ParkingRepository.distance(from: $0.location.coordinate, to: coordinate) <= 75
                }) == true {
                    return true
                }
            }
        }
        return false
    }

    private struct Candidate {
        let location: StaticParkingLocation
        let rule: ResolvedParkingRule
        let distance: Double
        let prediction: AvailabilityPrediction?

        var isOpenStreetMap: Bool {
            location.source.id == "openstreetmap-victoria-parking"
        }
    }

    private struct SearchEntry: Sendable {
        let location: StaticParkingLocation
        let normalizedText: String
        let tokens: Set<String>
    }

    private enum StaticResolution: Sendable {
        case eligible(ResolvedParkingRule, AvailabilityPrediction?)
        case ineligible
    }

    private struct ResolutionPlanKey: Equatable, Sendable {
        let arrivalMinute: Int
        let durationMinutes: Int
        let isPublicHoliday: Bool

        init(plan: ParkingPlan) {
            arrivalMinute = Int(plan.arrival.timeIntervalSince1970) / 60
            durationMinutes = plan.durationMinutes
            isPublicHoliday = plan.isPublicHoliday
        }
    }

    private struct QueryKey: Hashable, Sendable {
        let south: Int
        let west: Int
        let north: Int
        let east: Int
        let zoom: Int
        let arrivalMinute: Int
        let durationMinutes: Int
        let isPublicHoliday: Bool

        init(viewport: ParkingViewport, plan: ParkingPlan) {
            south = Int((viewport.south * 100_000).rounded())
            west = Int((viewport.west * 100_000).rounded())
            north = Int((viewport.north * 100_000).rounded())
            east = Int((viewport.east * 100_000).rounded())
            zoom = Int((viewport.zoomLevel * 10).rounded())
            arrivalMinute = Int(plan.arrival.timeIntervalSince1970) / 60
            durationMinutes = plan.durationMinutes
            isPublicHoliday = plan.isPublicHoliday
        }
    }

    private struct GridKey: Hashable {
        let row: Int
        let column: Int
    }

    private struct SpatialKey: Hashable {
        let latitude: Int
        let longitude: Int

        init(coordinate: Coordinate) {
            latitude = Int((coordinate.latitude * 1_000).rounded(.down))
            longitude = Int((coordinate.longitude * 1_000).rounded(.down))
        }

        init(latitude: Int, longitude: Int) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}

import Foundation

actor ParkingRepository {
    private struct HistoryKey: Hashable {
        let segmentKey: String
        let weekday: Int
    }

    private struct CacheKey: Hashable {
        let south: Int
        let west: Int
        let north: Int
        let east: Int
        let zoomBucket: Int
        let arrivalBucket: Int
        let durationMinutes: Int
    }

    private let api: any ParkingAPIProviding
    private let metadata: [Int: ZoneMetadata]
    private let restrictions: [Int: [RestrictionRecord]]
    private var historyBySegmentAndWeekday: [HistoryKey: [HistoricalBucket]]
    private let historyLoader: (@Sendable () throws -> [HistoricalBucket])?
    private let cacheTTL: TimeInterval
    private let restrictionEngine: RestrictionEngine
    private let forecastValidationBySegment: [String: ForecastValidation]
    private var cache: [CacheKey: TimedValue<ParkingRepositoryResult>] = [:]

    init(
        api: any ParkingAPIProviding,
        metadata: [ZoneMetadata],
        restrictions: [RestrictionRecord],
        history: [HistoricalBucket],
        historyLoader: (@Sendable () throws -> [HistoricalBucket])? = nil,
        cacheTTL: TimeInterval = 120,
        restrictionEngine: RestrictionEngine = RestrictionEngine(),
        forecastValidationBySegment: [String: ForecastValidation] = [:]
    ) {
        self.api = api
        self.metadata = Dictionary(uniqueKeysWithValues: metadata.map { ($0.zoneNumber, $0) })
        self.restrictions = Dictionary(grouping: restrictions, by: \.zoneNumber)
        self.historyBySegmentAndWeekday = Dictionary(
            grouping: history,
            by: { HistoryKey(segmentKey: $0.segmentKey, weekday: $0.weekday) }
        )
        self.historyLoader = historyLoader
        self.cacheTTL = cacheTTL
        self.restrictionEngine = restrictionEngine
        self.forecastValidationBySegment = forecastValidationBySegment
    }

    func refresh(
        viewport: ParkingViewport,
        plan: ParkingPlan,
        now: Date = .now,
        force: Bool = false
    ) async throws -> ParkingRepositoryResult {
        let queryViewport = viewport.padded(by: 0.2)
        let key = CacheKey(
            south: Int((queryViewport.south * 1_000).rounded()),
            west: Int((queryViewport.west * 1_000).rounded()),
            north: Int((queryViewport.north * 1_000).rounded()),
            east: Int((queryViewport.east * 1_000).rounded()),
            zoomBucket: Int(viewport.zoomLevel.rounded(.down)),
            arrivalBucket: Int(plan.arrival.timeIntervalSince1970) / (15 * 60),
            durationMinutes: plan.durationMinutes
        )
        if !force, let cached = cache[key]?.value(ifFreshAt: now, ttl: cacheTTL) { return cached }

        do {
            let aggregates = try await api.fetchZoneCounts(
                near: viewport.center, radiusMetres: queryViewport.queryRadiusMetres,
                since: now.addingTimeInterval(-AvailabilityEngine.trustCutoff)
            )
            let stats = AvailabilityEngine.group(aggregates: aggregates, now: now)
            guard !stats.isEmpty else {
                try loadHistoryIfNeeded()
                return try typicalResult(viewport: queryViewport, plan: plan, now: now)
            }
            let zones = makeLiveZones(stats: stats, viewport: queryViewport, plan: plan, now: now)
            let result = ParkingRepositoryResult(
                zones: markBestBet(zones),
                mode: .live,
                checkedAt: now,
                notice: notice(for: zones, plan: plan, now: now)
            )
            cache[key] = TimedValue(value: result, storedAt: now)
            return result
        } catch {
            try loadHistoryIfNeeded()
            return try typicalResult(viewport: queryViewport, plan: plan, now: now)
        }
    }

    func vacantBays(zoneNumber: Int, now: Date = .now) async throws -> [Coordinate] {
        try await api.fetchVacantBays(zoneNumber: zoneNumber, since: now.addingTimeInterval(-AvailabilityEngine.trustCutoff))
            .filter { $0.status == .unoccupied && now.timeIntervalSince($0.timestamp) <= AvailabilityEngine.trustCutoff }
            .map(\.coordinate)
    }

    private func makeLiveZones(stats: [Int: AvailabilityStats], viewport: ParkingViewport, plan: ParkingPlan, now: Date) -> [ParkingZone] {
        stats.compactMap { zoneNumber, availability in
            guard let metadata = metadata[zoneNumber], viewport.contains(metadata.coordinate), availability.total > 0,
                  let legality = legalDetails(zoneNumber: zoneNumber, plan: plan) else { return nil }
            let walking = Self.distance(from: metadata.coordinate, to: viewport.center)
            let profile = historicalProfile(for: metadata, at: plan.arrival)
            let horizonMinutes = max(0, Int(plan.arrival.timeIntervalSince(now) / 60))
            let prediction = PredictionEngine.estimate(
                liveAvailable: availability.available,
                trustedBayCount: availability.total,
                historicalOccupiedRatio: profile?.occupiedRatio,
                etaMinutes: horizonMinutes,
                validation: forecastValidationBySegment[metadata.segmentKey],
                forecastDate: plan.arrival
            )
            return ParkingZone(
                zoneNumber: zoneNumber,
                metadata: metadata,
                available: availability.available,
                total: availability.total,
                restrictionLabel: legality.label,
                payment: legality.payment,
                prediction: prediction,
                walkingMetres: walking,
                newestTimestamp: availability.newestTimestamp,
                mode: .live,
                schedule: restrictionEngine.weeklySchedule(restrictions[zoneNumber] ?? [], plan: plan),
                isBestBet: false
            )
        }
    }

    private func typicalResult(viewport: ParkingViewport, plan: ParkingPlan, now: Date) throws -> ParkingRepositoryResult {
        let zones: [ParkingZone] = metadata.values.compactMap { metadata in
            let walking = Self.distance(from: metadata.coordinate, to: viewport.center)
            guard viewport.contains(metadata.coordinate),
                  let legality = legalDetails(zoneNumber: metadata.zoneNumber, plan: plan),
                  let profile = historicalProfile(for: metadata, at: plan.arrival) else { return nil }
            let prediction = PredictionEngine.historicalEstimate(
                capacity: metadata.sensorCount, occupiedRatio: profile.occupiedRatio,
                horizonMinutes: max(0, Int(plan.arrival.timeIntervalSince(now) / 60)),
                validation: forecastValidationBySegment[metadata.segmentKey], forecastDate: plan.arrival
            )
            guard let expected = prediction.expectedAvailable else { return nil }
            return ParkingZone(
                zoneNumber: metadata.zoneNumber,
                metadata: metadata,
                available: Int(expected.rounded(.down)),
                total: metadata.sensorCount,
                restrictionLabel: legality.label,
                payment: legality.payment,
                prediction: prediction,
                walkingMetres: walking,
                newestTimestamp: nil,
                mode: .typical,
                schedule: restrictionEngine.weeklySchedule(restrictions[metadata.zoneNumber] ?? [], plan: plan),
                isBestBet: false
            )
        }
        guard !zones.isEmpty else { throw ParkingAPIError.invalidResponse }
        return ParkingRepositoryResult(
            zones: markBestBet(zones),
            mode: .typical,
            checkedAt: nil,
            notice: "Typical availability · live sensors are unavailable or stale"
        )
    }

    private func legalDetails(zoneNumber: Int, plan: ParkingPlan) -> (label: String, payment: ParkingPaymentStatus)? {
        switch restrictionEngine.resolve(restrictions[zoneNumber] ?? [], plan: plan) {
        case .permitted(let rule): return (rule.plainEnglish, rule.payment)
        case .unrestricted: return ("No timed limit right now", .free)
        case .unsuitable: return nil
        }
    }

    private func historicalProfile(for metadata: ZoneMetadata, at date: Date) -> HistoricalBucket? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let weekday = calendar.component(.weekday, from: date)
        let interval = (calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)) / 15
        let matching = historyBySegmentAndWeekday[HistoryKey(segmentKey: metadata.segmentKey, weekday: weekday)] ?? []
        return matching.first {
            $0.interval == interval && ($0.observationState?.supportsNumericForecast ?? true)
        }
    }

    private func loadHistoryIfNeeded() throws {
        guard historyBySegmentAndWeekday.isEmpty, let historyLoader else { return }
        historyBySegmentAndWeekday = Dictionary(
            grouping: try historyLoader(),
            by: { HistoryKey(segmentKey: $0.segmentKey, weekday: $0.weekday) }
        )
    }

    private func markBestBet(_ zones: [ParkingZone]) -> [ParkingZone] {
        let candidates = zones.compactMap { zone -> RankingCandidate? in
            guard zone.prediction.hasNumericForecast,
                  let expected = zone.prediction.expectedAvailable else { return nil }
            return RankingCandidate(
                zoneNumber: zone.zoneNumber, predictedAvailable: expected,
                walkingMetres: zone.walkingMetres, probabilityAtLeastOne: zone.prediction.probabilityAtLeastOne
            )
        }
        let ranked = RankingEngine.rank(candidates)
        guard let best = ranked.first?.zoneNumber else {
            return zones.sorted { $0.walkingMetres < $1.walkingMetres }
        }
        let rank = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($0.element.zoneNumber, $0.offset) })
        return zones.map { zone in
            ParkingZone(
                zoneNumber: zone.zoneNumber,
                metadata: zone.metadata,
                available: zone.available,
                total: zone.total,
                restrictionLabel: zone.restrictionLabel,
                payment: zone.payment,
                prediction: zone.prediction,
                walkingMetres: zone.walkingMetres,
                newestTimestamp: zone.newestTimestamp,
                mode: zone.mode,
                schedule: zone.schedule,
                isBestBet: zone.zoneNumber == best
            )
        }.sorted { (rank[$0.zoneNumber] ?? .max) < (rank[$1.zoneNumber] ?? .max) }
    }

    private func notice(for zones: [ParkingZone], plan: ParkingPlan, now: Date) -> String {
        guard !zones.isEmpty else {
            return "No nearby on-street parking fits a \(plan.selectionDescription) stay. Try another duration or an off-street option."
        }
        if abs(plan.arrival.timeIntervalSince(now)) <= 5 * 60 {
            return "\(plan.selectionDescription) stay · live availability · checked just now"
        }
        if zones.contains(where: { $0.prediction.hasNumericForecast }) {
            return "\(plan.selectionDescription) stay · forecast for planned arrival · refreshed just now"
        }
        return "\(plan.selectionDescription) stay · current sensor state is not a forecast for the planned arrival"
    }

    static func distance(from lhs: Coordinate, to rhs: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

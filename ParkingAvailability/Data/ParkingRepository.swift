import Foundation

actor ParkingRepository {
    private struct HistoryKey: Hashable {
        let segmentKey: String
        let weekday: Int
    }

    private struct CacheKey: Hashable {
        let latitude: Int
        let longitude: Int
        let duration: StayDuration
    }

    private let api: any ParkingAPIProviding
    private let metadata: [Int: ZoneMetadata]
    private let restrictions: [Int: [RestrictionRecord]]
    private var historyBySegmentAndWeekday: [HistoryKey: [HistoricalBucket]]
    private let historyLoader: (@Sendable () throws -> [HistoricalBucket])?
    private let cacheTTL: TimeInterval
    private let restrictionEngine: RestrictionEngine
    private var cache: [CacheKey: TimedValue<ParkingRepositoryResult>] = [:]

    init(
        api: any ParkingAPIProviding,
        metadata: [ZoneMetadata],
        restrictions: [RestrictionRecord],
        history: [HistoricalBucket],
        historyLoader: (@Sendable () throws -> [HistoricalBucket])? = nil,
        cacheTTL: TimeInterval = 120,
        restrictionEngine: RestrictionEngine = RestrictionEngine()
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
    }

    func refresh(
        destination: Coordinate,
        duration: StayDuration,
        now: Date = .now,
        force: Bool = false
    ) async throws -> ParkingRepositoryResult {
        let key = CacheKey(latitude: Int((destination.latitude * 10_000).rounded()), longitude: Int((destination.longitude * 10_000).rounded()), duration: duration)
        if !force, let cached = cache[key]?.value(ifFreshAt: now, ttl: cacheTTL) { return cached }

        do {
            let aggregates = try await api.fetchZoneCounts(near: destination, radiusMetres: 700, since: now.addingTimeInterval(-AvailabilityEngine.trustCutoff))
            let stats = AvailabilityEngine.group(aggregates: aggregates, now: now)
            guard !stats.isEmpty else {
                try loadHistoryIfNeeded()
                return try typicalResult(destination: destination, duration: duration, now: now)
            }
            let zones = makeLiveZones(stats: stats, destination: destination, duration: duration, now: now)
            let result = ParkingRepositoryResult(
                zones: markBestBet(zones),
                mode: .live,
                checkedAt: now,
                notice: zones.isEmpty
                    ? "No nearby on-street parking fits a \(duration.selectionDescription) stay. Try another duration or an off-street option."
                    : "\(duration.selectionDescription) stay · live availability · checked just now"
            )
            cache[key] = TimedValue(value: result, storedAt: now)
            return result
        } catch {
            try loadHistoryIfNeeded()
            return try typicalResult(destination: destination, duration: duration, now: now)
        }
    }

    func vacantBays(zoneNumber: Int, now: Date = .now) async throws -> [Coordinate] {
        try await api.fetchVacantBays(zoneNumber: zoneNumber, since: now.addingTimeInterval(-AvailabilityEngine.trustCutoff))
            .filter { $0.status == .unoccupied && now.timeIntervalSince($0.timestamp) <= AvailabilityEngine.trustCutoff }
            .map(\.coordinate)
    }

    private func makeLiveZones(stats: [Int: AvailabilityStats], destination: Coordinate, duration: StayDuration, now: Date) -> [ParkingZone] {
        stats.compactMap { zoneNumber, availability in
            guard let metadata = metadata[zoneNumber], availability.total > 0,
                  let legality = legalDetails(zoneNumber: zoneNumber, duration: duration, now: now) else { return nil }
            let walking = Self.distance(from: metadata.coordinate, to: destination)
            let profile = historicalProfile(for: metadata, at: now.addingTimeInterval(15 * 60))
            let prediction = PredictionEngine.estimate(
                liveAvailable: availability.available,
                trustedBayCount: availability.total,
                historicalOccupiedRatio: profile?.occupiedRatio,
                etaMinutes: 15,
                sampleCount: profile?.sampleCount ?? 0
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
                isBestBet: false
            )
        }
    }

    private func typicalResult(destination: Coordinate, duration: StayDuration, now: Date) throws -> ParkingRepositoryResult {
        let zones: [ParkingZone] = metadata.values.compactMap { metadata in
            let walking = Self.distance(from: metadata.coordinate, to: destination)
            guard walking <= 700,
                  let legality = legalDetails(zoneNumber: metadata.zoneNumber, duration: duration, now: now),
                  let profile = historicalProfile(for: metadata, at: now) else { return nil }
            let expected = Double(metadata.sensorCount) * (1 - min(1, max(0, profile.occupiedRatio)))
            let prediction = PredictionEngine.estimate(
                liveAvailable: Int(expected.rounded()),
                trustedBayCount: metadata.sensorCount,
                historicalOccupiedRatio: profile.occupiedRatio,
                etaMinutes: 180,
                sampleCount: profile.sampleCount
            )
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

    private func legalDetails(zoneNumber: Int, duration: StayDuration, now: Date) -> (label: String, payment: ParkingPaymentStatus)? {
        switch restrictionEngine.resolve(restrictions[zoneNumber] ?? [], at: now, for: duration) {
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
        return matching.min(by: { abs($0.interval - interval) < abs($1.interval - interval) })
    }

    private func loadHistoryIfNeeded() throws {
        guard historyBySegmentAndWeekday.isEmpty, let historyLoader else { return }
        historyBySegmentAndWeekday = Dictionary(
            grouping: try historyLoader(),
            by: { HistoryKey(segmentKey: $0.segmentKey, weekday: $0.weekday) }
        )
    }

    private func markBestBet(_ zones: [ParkingZone]) -> [ParkingZone] {
        let candidates = zones.map {
            RankingCandidate(zoneNumber: $0.zoneNumber, predictedAvailable: $0.prediction.expectedAvailable, walkingMetres: $0.walkingMetres, confidence: $0.prediction.confidence)
        }
        let ranked = RankingEngine.rank(candidates)
        guard let best = ranked.first?.zoneNumber else { return zones }
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
                isBestBet: zone.zoneNumber == best
            )
        }.sorted { (rank[$0.zoneNumber] ?? .max) < (rank[$1.zoneNumber] ?? .max) }
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

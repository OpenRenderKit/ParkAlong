import Foundation

actor StaticParkingRepository: StaticParkingProviding {
    private var locations: [StaticParkingLocation]
    private var loader: (@Sendable () throws -> [StaticParkingLocation])?
    private var didAttemptLoad: Bool
    private let radiusMetres: Double
    private let resultLimit: Int
    private let ruleResolver: ParkingRuleResolver

    init(
        locations: [StaticParkingLocation],
        radiusMetres: Double = 2_000,
        resultLimit: Int = 24,
        ruleResolver: ParkingRuleResolver = ParkingRuleResolver()
    ) {
        self.locations = locations
        self.loader = nil
        self.didAttemptLoad = true
        self.radiusMetres = radiusMetres
        self.resultLimit = resultLimit
        self.ruleResolver = ruleResolver
    }

    init(
        loader: @escaping @Sendable () throws -> [StaticParkingLocation],
        radiusMetres: Double = 2_000,
        resultLimit: Int = 24,
        ruleResolver: ParkingRuleResolver = ParkingRuleResolver()
    ) {
        self.locations = []
        self.loader = loader
        self.didAttemptLoad = false
        self.radiusMetres = radiusMetres
        self.resultLimit = resultLimit
        self.ruleResolver = ruleResolver
    }

    func options(near destination: Coordinate, duration: StayDuration, at date: Date) async -> [ParkingOption] {
        let candidates = loadLocationsIfNeeded().compactMap { location -> Candidate? in
            let distance = ParkingRepository.distance(from: location.coordinate, to: destination)
            guard distance <= radiusMetres,
                  let rule = ruleResolver.resolve(location: location, at: date, duration: duration),
                  rule.isEligible else { return nil }
            let prediction = location.predictionEvidence.flatMap {
                PredictionEngine.staticEstimate(
                    capacity: location.capacity,
                    evidence: $0,
                    archetype: location.archetype,
                    context: demandContext(for: location, at: date)
                )
            }
            return Candidate(location: location, rule: rule, distance: distance, prediction: prediction)
        }
        .sorted {
            if $0.isOpenStreetMap != $1.isOpenStreetMap { return !$0.isOpenStreetMap }
            return $0.distance < $1.distance
        }

        var accepted: [Candidate] = []
        for candidate in candidates {
            if candidate.isOpenStreetMap,
               accepted.contains(where: { !$0.isOpenStreetMap && ParkingRepository.distance(from: $0.location.coordinate, to: candidate.location.coordinate) <= 75 }) {
                continue
            }
            accepted.append(candidate)
            if accepted.count == resultLimit { break }
        }
        return accepted.map(makeOption)
    }

    private func loadLocationsIfNeeded() -> [StaticParkingLocation] {
        guard !didAttemptLoad else { return locations }
        didAttemptLoad = true
        defer { loader = nil }
        locations = (try? loader?()) ?? []
        return locations
    }

    private func makeOption(_ candidate: Candidate) -> ParkingOption {
        let location = candidate.location
        let kind: ParkingOptionKind = location.kind == .onStreet ? .onStreet : .offStreet
        let sourceAgeWarning = location.source.datasetUpdatedAt == nil
            ? "Location only · availability is not live"
            : "Static data checked by ParkAlong · availability is not live"
        let classification: ParkingDataClassification = candidate.prediction == nil ? location.classification : .predicted
        let available = candidate.prediction.map { Int($0.expectedAvailable.rounded(.down)) }
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
            sourceCheckedAt: location.source.checkedAt
        )
    }

    private func demandContext(for location: StaticParkingLocation, at date: Date) -> ParkingDemandContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return ParkingDemandContext(
            weekday: components.weekday ?? 1,
            minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            isPublicHoliday: false,
            isSchoolHoliday: false,
            clearWeatherIndex: 0.5,
            eventIntensity: 0,
            trafficIndex: 1,
            hourlyPriceCents: location.tariffs.first?.hourlyCents,
            maxStayMinutes: location.schedules.compactMap(\.maxStayMinutes).min()
        )
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
}

import Foundation

enum RankingEngine {
    static func rank(_ candidates: [RankingCandidate]) -> [RankedCandidate] {
        let maxAvailability = max(1, candidates.map(\.predictedAvailable).max() ?? 1)
        return candidates.map { candidate in
            let availability = min(1, max(0, candidate.predictedAvailable / maxAvailability))
            let distance = max(0, 1 - min(candidate.walkingMetres, 1_500) / 1_500)
            let probability = min(1, max(0, candidate.probabilityAtLeastOne ?? 0))
            return RankedCandidate(zoneNumber: candidate.zoneNumber, score: 0.7 * availability + 0.2 * distance + 0.1 * probability)
        }.sorted {
            if $0.score == $1.score { return $0.zoneNumber < $1.zoneNumber }
            return $0.score > $1.score
        }
    }
}

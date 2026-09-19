import Foundation

enum RankingEngine {
    static let policyVersion = "availability-proximity-v1"

    static func rank(_ candidates: [RankingCandidate]) -> [RankedCandidate] {
        let validCandidates = candidates.filter { candidate in
            candidate.predictedAvailable.isFinite
                && candidate.predictedAvailable >= 0
                && candidate.straightLineMetres.isFinite
                && candidate.straightLineMetres >= 0
                && (candidate.probabilityAtLeastOne?.isFinite ?? true)
        }
        let maxAvailability = max(1, validCandidates.map(\.predictedAvailable).max() ?? 1)
        return validCandidates.map { candidate in
            let availability = min(1, max(0, candidate.predictedAvailable / maxAvailability))
            let distance = max(0, 1 - min(candidate.straightLineMetres, 1_500) / 1_500)
            let probability = min(1, max(0, candidate.probabilityAtLeastOne ?? 0))
            let contributions = RankingFactorContributions(
                predictedAvailability: 0.7 * availability,
                straightLineProximity: 0.2 * distance,
                probabilityAtLeastOne: 0.1 * probability
            )
            return RankedCandidate(
                zoneNumber: candidate.zoneNumber,
                score: contributions.predictedAvailability
                    + contributions.straightLineProximity
                    + contributions.probabilityAtLeastOne,
                contributions: contributions,
                policyVersion: policyVersion
            )
        }.sorted {
            if $0.score == $1.score { return $0.zoneNumber < $1.zoneNumber }
            return $0.score > $1.score
        }
    }

    static func explanation(relativeTo destination: String) -> String {
        let name = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = name.isEmpty ? "the selected destination" : name
        return "We compare street parking found in this map area. Expected available spaces matter most, followed by straight-line distance to \(resolved), then the chance of finding a space."
    }
}

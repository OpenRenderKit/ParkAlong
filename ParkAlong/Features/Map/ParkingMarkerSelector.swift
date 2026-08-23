import Foundation

/// Keeps map content useful and tappable without letting location-only warnings cover the map.
enum ParkingMarkerSelector {
    static func markerBudget(for zoomLevel: Double) -> Int {
        switch zoomLevel {
        case ..<10: 20
        case ..<13: 28
        case ..<15: 36
        default: 48
        }
    }

    static func select<S: Sequence>(
        options: S,
        selectedID: String?,
        viewport: ParkingViewport
    ) -> [ParkingOption] where S.Element == ParkingOption {
        let all = options.sorted(by: priorityOrder)
        let budget = markerBudget(for: viewport.zoomLevel)
        let selected = selectedID.flatMap { id in all.first(where: { $0.id == id }) }
        let useful = all.filter { option in
            option.classification == .verifiedLive
                || option.classification == .predicted
                || option.clusterCount != nil
        }
        var result = Array(useful.prefix(budget))
        var selectedIDs = Set(result.map(\.id))

        if let selected, !selectedIDs.contains(selected.id) {
            if result.count == budget, let removed = result.popLast() {
                selectedIDs.remove(removed.id)
            }
            result.append(selected)
            selectedIDs.insert(selected.id)
        }

        let remainingCapacity = max(0, budget - result.count)
        let lowValueBudget = useful.isEmpty ? min(12, remainingCapacity) : min(4, remainingCapacity)
        guard lowValueBudget > 0 else { return result.sorted(by: priorityOrder) }

        let warnings = all.filter { !selectedIDs.contains($0.id) && $0.clusterCount == nil }
        let gridDimension = max(3, Int(ceil(sqrt(Double(lowValueBudget) * 1.5))))
        var occupiedCells = Set<GridCell>()
        var distributed: [ParkingOption] = []
        distributed.reserveCapacity(lowValueBudget)

        for option in warnings {
            let cell = gridCell(for: option.coordinate, viewport: viewport, dimension: gridDimension)
            guard occupiedCells.insert(cell).inserted else { continue }
            distributed.append(option)
            if distributed.count == lowValueBudget { break }
        }

        if distributed.count < lowValueBudget {
            let distributedIDs = Set(distributed.map(\.id))
            distributed.append(contentsOf: warnings.lazy.filter { !distributedIDs.contains($0.id) }.prefix(lowValueBudget - distributed.count))
        }
        result.append(contentsOf: distributed)
        return result.sorted(by: priorityOrder)
    }

    private static func priorityOrder(_ lhs: ParkingOption, _ rhs: ParkingOption) -> Bool {
        let lhsRank = priority(of: lhs)
        let rhsRank = priority(of: rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.isBestBet != rhs.isBestBet { return lhs.isBestBet }
        if lhs.walkingMetres != rhs.walkingMetres { return lhs.walkingMetres < rhs.walkingMetres }
        return lhs.id < rhs.id
    }

    private static func priority(of option: ParkingOption) -> Int {
        switch option.classification {
        case .verifiedLive: return 0
        case .predicted: return 1
        case .staticOnly, .staleHistorical:
            if option.clusterCount != nil { return 2 }
            if option.provider.localizedCaseInsensitiveContains("OpenStreetMap") { return 4 }
            return 3
        }
    }

    private static func gridCell(
        for coordinate: Coordinate,
        viewport: ParkingViewport,
        dimension: Int
    ) -> GridCell {
        let row = Int(((coordinate.latitude - viewport.south) / max(viewport.latitudeSpan, 0.000_001) * Double(dimension)).rounded(.down))
        let column = Int(((coordinate.longitude - viewport.west) / max(viewport.longitudeSpan, 0.000_001) * Double(dimension)).rounded(.down))
        return GridCell(
            row: min(dimension - 1, max(0, row)),
            column: min(dimension - 1, max(0, column))
        )
    }

    private struct GridCell: Hashable {
        let row: Int
        let column: Int
    }
}

import Foundation

struct StaticParkingSpatialQuery: Sendable {
    let locations: [StaticParkingLocation]
    let inspectedLocationCount: Int
}

/// An immutable latitude/longitude grid built once for the statewide catalog.
/// Street-scale queries inspect only nearby grid cells instead of every Victorian record.
struct StaticParkingSpatialIndex: Sendable {
    private struct Cell: Hashable, Sendable {
        let latitude: Int
        let longitude: Int
    }

    private let locations: [StaticParkingLocation]
    private let buckets: [Cell: [Int]]
    private let occupiedCells: [Cell]
    private let cellSizeDegrees: Double

    init(locations: [StaticParkingLocation], cellSizeDegrees: Double = 0.02) {
        precondition(cellSizeDegrees > 0, "Spatial-index cells must have positive area")
        self.locations = locations
        self.cellSizeDegrees = cellSizeDegrees

        var buckets: [Cell: [Int]] = [:]
        buckets.reserveCapacity(locations.count / 2)
        for (index, location) in locations.enumerated() {
            buckets[Self.cell(for: location.coordinate, size: cellSizeDegrees), default: []].append(index)
        }
        self.buckets = buckets
        self.occupiedCells = buckets.keys.sorted {
            if $0.latitude != $1.latitude { return $0.latitude < $1.latitude }
            return $0.longitude < $1.longitude
        }
    }

    func locations(in viewport: ParkingViewport) -> [StaticParkingLocation] {
        query(in: viewport).locations
    }

    func query(in viewport: ParkingViewport) -> StaticParkingSpatialQuery {
        let minimum = cell(for: .init(latitude: viewport.south, longitude: viewport.west))
        let maximum = cell(for: .init(latitude: viewport.north, longitude: viewport.east))
        let latitudeCellCount = max(1, maximum.latitude - minimum.latitude + 1)
        let longitudeCellCount = max(1, maximum.longitude - minimum.longitude + 1)
        let requestedCellCount = latitudeCellCount.multipliedReportingOverflow(by: longitudeCellCount)

        var candidateIndices: [Int] = []
        if !requestedCellCount.overflow, requestedCellCount.partialValue <= occupiedCells.count * 2 {
            for latitude in minimum.latitude...maximum.latitude {
                for longitude in minimum.longitude...maximum.longitude {
                    candidateIndices.append(contentsOf: buckets[Cell(latitude: latitude, longitude: longitude)] ?? [])
                }
            }
        } else {
            for cell in occupiedCells where
                (minimum.latitude...maximum.latitude).contains(cell.latitude)
                && (minimum.longitude...maximum.longitude).contains(cell.longitude) {
                candidateIndices.append(contentsOf: buckets[cell] ?? [])
            }
        }

        candidateIndices.sort()
        let matches = candidateIndices.compactMap { index -> StaticParkingLocation? in
            let location = locations[index]
            return viewport.contains(location.coordinate) ? location : nil
        }
        return StaticParkingSpatialQuery(
            locations: matches,
            inspectedLocationCount: candidateIndices.count
        )
    }

    private func cell(for coordinate: Coordinate) -> Cell {
        Self.cell(for: coordinate, size: cellSizeDegrees)
    }

    private static func cell(for coordinate: Coordinate, size: Double) -> Cell {
        Cell(
            latitude: Int(floor(coordinate.latitude / size)),
            longitude: Int(floor(coordinate.longitude / size))
        )
    }
}

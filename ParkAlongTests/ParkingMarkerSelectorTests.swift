import XCTest
@testable import ParkAlong

final class ParkingMarkerSelectorTests: XCTestCase {
    private let viewport = ParkingViewport(
        south: -37.84, west: 144.92,
        north: -37.78, east: 145.00,
        zoomLevel: 14
    )

    func testDenseCBDKeepsEveryUsefulMarkerBeforeLocationOnlyWarnings() {
        let live = (0..<12).map { index in
            option(id: "live-\(index)", classification: .verifiedLive, available: index + 1, row: index / 4, column: index % 4)
        }
        let predicted = (0..<4).map { index in
            option(id: "predicted-\(index)", classification: .predicted, available: index + 1, row: index, column: 5)
        }
        let warnings = (0..<120).map { index in
            option(id: "warning-\(index)", classification: .staticOnly, available: nil, row: index / 12, column: index % 12)
        }

        let selected = ParkingMarkerSelector.select(
            options: warnings + predicted + live,
            selectedID: nil,
            viewport: viewport
        )

        XCTAssertTrue(Set(live.map(\.id)).isSubset(of: Set(selected.map(\.id))))
        XCTAssertTrue(Set(predicted.map(\.id)).isSubset(of: Set(selected.map(\.id))))
        XCTAssertLessThanOrEqual(
            selected.filter { $0.classification == .staticOnly || $0.classification == .staleHistorical }.count,
            4
        )
        XCTAssertLessThanOrEqual(selected.count, ParkingMarkerSelector.markerBudget(for: viewport.zoomLevel))
    }

    func testSelectedWarningRemainsVisibleWhenItWouldOtherwiseLoseDensitySelection() {
        let warnings = (0..<100).map { index in
            option(id: "warning-\(index)", classification: .staticOnly, available: nil, row: 2, column: 2)
        }

        let selected = ParkingMarkerSelector.select(
            options: warnings,
            selectedID: "warning-99",
            viewport: viewport
        )

        XCTAssertTrue(selected.contains(where: { $0.id == "warning-99" }))
    }

    func testDensitySelectionIsDeterministicAcrossInputOrdering() {
        let options = (0..<80).map { index in
            option(id: "warning-\(index)", classification: .staticOnly, available: nil, row: index / 10, column: index % 10)
        }

        let forward = ParkingMarkerSelector.select(options: options, selectedID: nil, viewport: viewport)
        let reverse = ParkingMarkerSelector.select(options: options.reversed(), selectedID: nil, viewport: viewport)

        XCTAssertEqual(forward.map(\.id), reverse.map(\.id))
    }

    func testSuburbanViewShowsUsefulLocationCoverageWithoutFillingTheMapWithWarnings() {
        let warnings = (0..<90).map { index in
            option(id: "suburban-\(index)", classification: .staticOnly, available: nil, row: index / 10, column: index % 10)
        }
        let suburban = ParkingViewport(
            south: -37.95, west: 144.75,
            north: -37.75, east: 145.05,
            zoomLevel: 12
        )

        let selected = ParkingMarkerSelector.select(options: warnings, selectedID: nil, viewport: suburban)

        XCTAssertGreaterThan(selected.count, 8)
        XCTAssertLessThanOrEqual(selected.count, 12)
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
    }

    private func option(
        id: String,
        classification: ParkingDataClassification,
        available: Int?,
        row: Int,
        column: Int
    ) -> ParkingOption {
        let latitude = viewport.south + (Double(row) + 0.5) * viewport.latitudeSpan / 12
        let longitude = viewport.west + (Double(column) + 0.5) * viewport.longitudeSpan / 12
        return ParkingOption(
            id: id,
            kind: .offStreet,
            title: id,
            locationLabel: "Fixture",
            coordinate: .init(latitude: latitude, longitude: longitude),
            availabilityState: available.map { $0 > 0 ? .available : .occupied } ?? .unknown,
            available: available,
            total: available.map { $0 + 5 },
            restrictionLabel: "Fixture",
            restrictionWindow: "Fixture",
            activeNow: true,
            price: .init(primaryText: "Fixture", detail: "Fixture", provider: "Fixture", actionLabel: nil, actionURL: nil),
            provider: "Fixture",
            sourceTimestamp: classification == .verifiedLive ? Date(timeIntervalSince1970: 1_777_000_000) : nil,
            walkingMetres: Double(row * 100 + column),
            prediction: nil,
            isBestBet: id == "live-0",
            zoneNumber: nil,
            classification: classification,
            warningText: classification.needsWarning ? "Not live" : nil,
            sourceDatasetAt: nil,
            sourceCheckedAt: nil,
            schedule: [],
            clusterCount: nil,
            clusterViewport: nil
        )
    }
}

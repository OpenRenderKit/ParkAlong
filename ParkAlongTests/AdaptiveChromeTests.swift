import XCTest
@testable import ParkAlong

final class AdaptiveChromeTests: XCTestCase {
    func testLiquidGlassIsUsedWhenSupportedAndTransparencyIsAllowed() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(
                supportsLiquidGlass: true,
                reduceTransparency: false
            ),
            .liquidGlass
        )
    }

    func testReduceTransparencyAlwaysUsesOpaqueSurface() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(
                supportsLiquidGlass: true,
                reduceTransparency: true
            ),
            .opaque
        )
    }

    func testOlderSystemsUseMaterialSurface() {
        XCTAssertEqual(
            AdaptiveChromePolicy.surfaceKind(
                supportsLiquidGlass: false,
                reduceTransparency: false
            ),
            .material
        )
    }
}

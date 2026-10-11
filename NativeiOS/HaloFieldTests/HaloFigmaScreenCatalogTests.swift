import XCTest
@testable import HaloField

final class HaloFigmaScreenCatalogTests: XCTestCase {
    func testEveryOneOfThe84FigmaScreensHasAnExactSourceNode() {
        let screens = HaloFigmaScreenCatalog.screens
        XCTAssertEqual(screens.count, 84)
        XCTAssertEqual(screens.map(\.number), Array(1...84))
        XCTAssertEqual(Set(screens.map(\.figmaNode)).count, 84)
        XCTAssertEqual(Set(screens.map(\.name)).count, 84)
        XCTAssertTrue(screens.allSatisfy { $0.figmaURL.scheme == "https" })
        XCTAssertEqual(screens.first?.figmaNode, "2:2")
        XCTAssertEqual(screens.last?.figmaNode, "8:581")
    }

    func testPreviewCoverageNeverClaimsUnbuiltScreensAreNative() {
        let screens = HaloFigmaScreenCatalog.screens
        let previewIDs = screens.filter(\.nativePreviewAvailable).map(\.number)
        XCTAssertEqual(previewIDs, Array(73...84))
        XCTAssertEqual(screens.filter { !$0.nativePreviewAvailable }.count, 72)
        XCTAssertEqual(HaloFigmaScreenCatalog.screen(77)?.name, "Job Opportunity · Apply")
        XCTAssertEqual(HaloFigmaScreenCatalog.screen(80)?.name, "Contractor · Available For Work")
        XCTAssertNil(HaloFigmaScreenCatalog.screen(85))
        XCTAssertNil(HaloFigmaScreenCatalog.screen(0))
    }

    func testEveryScreenBelongsToAnIntentionalWorkflowArea() {
        for area in HaloFigmaArea.allCases {
            XCTAssertTrue(
                HaloFigmaScreenCatalog.screens.contains(where: { $0.area == area }),
                "Missing screens in workflow area \(area.rawValue)"
            )
        }
        XCTAssertTrue(
            HaloFigmaScreenCatalog.screens
                .filter { $0.nativePreviewAvailable }
                .allSatisfy { $0.area == .marketplace }
        )
    }
}

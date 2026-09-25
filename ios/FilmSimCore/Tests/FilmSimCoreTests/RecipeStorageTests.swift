import XCTest
@testable import FilmSimCore

final class RecipeStorageTests: XCTestCase {
    func testRoundTrip() {
        var r = Recipe()
        r.filmSimulation = .classicChrome
        r.exposureEV = -0.25
        r.wbShiftR = 2
        r.highlight = 1
        r.grainStrength = .weak
        r.grainSize = .large
        XCTAssertEqual(Recipe.decoded(from: r.encoded), r)
    }

    func testEmptyOrBrokenDataFallsBackToDefault() {
        XCTAssertEqual(Recipe.decoded(from: Data()), Recipe())
        XCTAssertEqual(Recipe.decoded(from: Data("not json".utf8)), Recipe())
        XCTAssertEqual(Recipe.decoded(from: Data(#"{"filmSimulation":"kodachrome"}"#.utf8)), Recipe())
    }

    func testAdjustmentSummaryListsOnlyWhatDiffersFromDefault() {
        XCTAssertEqual(Recipe().adjustmentSummary, "")
        var r = Recipe()
        r.filmSimulation = .classicChrome
        XCTAssertEqual(r.adjustmentSummary, "")
        r.exposureEV = 0.5
        r.wbShiftB = -3
        r.shadow = 2
        r.grainStrength = .strong
        XCTAssertEqual(r.adjustmentSummary, "EV +0.50 · WB R+0 B-3 · S +2 · Grain strong small")
    }
}

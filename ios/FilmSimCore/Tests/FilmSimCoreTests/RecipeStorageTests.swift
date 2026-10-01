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
}

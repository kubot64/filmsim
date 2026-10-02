import XCTest

@testable import FilmSimCore

final class WarmHueTests: XCTestCase {
    func testKeepsLuma() {
        let rgb: SIMD3<Double> = [0.8, 0.45, 0.2]
        let out = WarmHue.evaluate(rgb)
        XCTAssertEqual((out * BT709.luma).sum(), (rgb * BT709.luma).sum(), accuracy: 1e-12)
    }

    func testOnlyProvia() {
        XCTAssertTrue(FilmSimulation.provia.usesWarmHue)
        XCTAssertFalse(FilmSimulation.classicChrome.usesWarmHue)
        XCTAssertFalse(FilmSimulation.portra400vc.usesWarmHue)
    }

    func testShoulderIsForFujifilmLooksOnly() {
        XCTAssertTrue(FilmSimulation.provia.usesXSeriesShoulder)
        XCTAssertTrue(FilmSimulation.classicChrome.usesXSeriesShoulder)
        XCTAssertFalse(FilmSimulation.portra400vc.usesXSeriesShoulder)
    }
}

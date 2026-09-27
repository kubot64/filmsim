import XCTest
@testable import FilmSimCore

final class WarmHueTests: XCTestCase {
    func testGoldenPointsMatchPython() {
        // Literals from research/tests/test_hue.py (test_fitted_rotation_golden_points).
        let cases: [(SIMD3<Double>, SIMD3<Double>)] = [
            ([0.8, 0.2, 0.1], [0.8144788117, 0.1906360983, 0.1501228138]),
            ([0.9, 0.55, 0.2], [0.9390028460, 0.5337492135, 0.2461296049]),
            ([0.7, 0.7, 0.2], [0.7288390912, 0.6909850233, 0.2043811709]),
            ([0.2, 0.4, 0.9], [0.2, 0.4, 0.9]),
            ([0.5, 0.5, 0.5], [0.5, 0.5, 0.5]),
        ]
        for (rgb, expected) in cases {
            let out = WarmHue.evaluate(rgb)
            for c in 0..<3 { XCTAssertEqual(out[c], expected[c], accuracy: 1e-9, "\(rgb)") }
        }
    }

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

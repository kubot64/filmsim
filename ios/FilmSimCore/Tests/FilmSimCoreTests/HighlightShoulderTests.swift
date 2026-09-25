import XCTest
@testable import FilmSimCore

final class HighlightShoulderTests: XCTestCase {
    private func grey(_ v: Double) -> SIMD3<Double> { [v, v, v] }

    func testKneeAndBelowStayPutAndWhiteStaysWhite() {
        for v in [0.0, 0.2, 0.45, 0.6, 1.0] {
            let out = HighlightShoulder.evaluate(grey(v))
            for c in 0..<3 { XCTAssertEqual(out[c], v, accuracy: 1e-12) }
        }
    }

    func testLiftsHighlightsMonotonically() {
        var previous = -1.0
        for i in 0...100 {
            let v = Double(i) / 100
            let out = HighlightShoulder.evaluate(grey(v))[0]
            XCTAssertGreaterThanOrEqual(out, previous)
            if v > 0.6 + 1e-9, v < 1 { XCTAssertGreaterThan(out, v) }
            previous = out
        }
    }

    func testKeepsRGBRatios() {
        let rgb: SIMD3<Double> = [0.9, 0.6, 0.5]
        let out = HighlightShoulder.evaluate(rgb)
        for c in 0..<3 { XCTAssertEqual(out[c] / out[0], rgb[c] / rgb[0], accuracy: 1e-12) }
    }

    func testGoldenPointsMatchPython() {
        // Literals from research/tests/test_tone.py (test_shoulder_golden_points).
        let cases: [(Double, Double)] = [
            (0.7, 0.721353129146), (0.8, 0.8472135955), (0.9, 0.94107653273), (0.95, 0.973618990031),
        ]
        for (v, expected) in cases {
            XCTAssertEqual(HighlightShoulder.evaluate(grey(v))[0], expected, accuracy: 1e-11)
        }
    }
}

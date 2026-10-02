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
}

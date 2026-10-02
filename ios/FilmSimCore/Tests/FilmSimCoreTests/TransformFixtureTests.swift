import XCTest
import simd

@testable import FilmSimCore

/// The Swift CPU functions give the research pipeline's outputs on every fixture input
/// (TransformFixtures). Both sides run the same double-precision formulas, so the only
/// differences are libm rounding (about 1e-15); 1e-12 leaves room for that and nothing else.
/// MetalKernelTests checks the GPU kernels against the same fixtures.
final class TransformFixtureTests: XCTestCase {
    private let accuracy = 1e-12

    func testFLog2EncodeMatchesPython() {
        for c in TransformFixtures.cases("flog2_encode") {
            XCTAssertEqual(FLog2.encode(c.in[0]), c.out[0], accuracy: accuracy, "\(c)")
        }
    }

    func testFLog2DecodeMatchesPython() {
        for c in TransformFixtures.cases("flog2_decode") {
            XCTAssertEqual(FLog2.decode(c.in[0]), c.out[0], accuracy: accuracy, "\(c)")
        }
    }

    func testGamutConversionsMatchPython() {
        let pairs: [(String, RGBSpace, RGBSpace)] = [
            ("gamut_p3_to_fgamut", .displayP3, .fGamut),
            ("gamut_fgamut_to_p3", .fGamut, .displayP3),
            ("gamut_bt709_to_fgamut", .bt709, .fGamut),
            ("gamut_fgamut_to_bt709", .fGamut, .bt709)
        ]
        for (name, src, dst) in pairs {
            let m = RGBSpace.conversion(from: src, to: dst)
            for c in TransformFixtures.cases(name) {
                assertEqual(m * c.rgbIn, c.rgbOut, "\(c)")
            }
        }
    }

    func testHighlightShoulderMatchesPython() {
        for c in TransformFixtures.cases("highlight_shoulder") {
            assertEqual(HighlightShoulder.evaluate(c.rgbIn), c.rgbOut, "\(c)")
        }
    }

    func testWarmHueMatchesPython() {
        for c in TransformFixtures.cases("warm_hue") {
            assertEqual(WarmHue.evaluate(c.rgbIn), c.rgbOut, "\(c)")
        }
    }

    func testToneCurveMatchesPython() {
        for c in TransformFixtures.cases("tone_curve") {
            XCTAssertEqual(
                ToneCurve.evaluate(c.in[0], highlight: c.tone.highlight, shadow: c.tone.shadow), c.out[0],
                accuracy: accuracy, "\(c)")
        }
    }

    func testGrainWeightMatchesPython() {
        for c in TransformFixtures.cases("grain_weight") {
            XCTAssertEqual(Grain.weight(luminance: c.in[0]), c.out[0], accuracy: accuracy, "\(c)")
        }
    }

    private func assertEqual(
        _ got: SIMD3<Double>, _ expected: SIMD3<Double>, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for ch in 0..<3 {
            XCTAssertEqual(
                got[ch], expected[ch], accuracy: accuracy, "channel \(ch) \(message)", file: file, line: line)
        }
    }
}

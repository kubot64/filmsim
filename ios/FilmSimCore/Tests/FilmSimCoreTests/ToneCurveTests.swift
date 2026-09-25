import XCTest
@testable import FilmSimCore

final class ToneCurveTests: XCTestCase {
    func testZeroIsIdentity() {
        for x in stride(from: 0.0, through: 1.0, by: 0.125) {
            XCTAssertEqual(ToneCurve.evaluate(x, highlight: 0, shadow: 0), x, accuracy: 1e-15)
        }
    }

    func testEndpointsAndMidpointStayPut() {
        for x in [0.0, 0.5, 1.0] {
            XCTAssertEqual(ToneCurve.evaluate(x, highlight: 4, shadow: 4), x, accuracy: 1e-12)
        }
    }

    func testGoldenPointsMatchPython() {
        // Literals from research/tests/test_tone.py.
        XCTAssertEqual(ToneCurve.evaluate(0.75, highlight: 4, shadow: 0), 0.805528455647, accuracy: 1e-9)
        XCTAssertEqual(ToneCurve.evaluate(0.25, highlight: 0, shadow: 4), 0.189257114166, accuracy: 1e-9)
        XCTAssertEqual(ToneCurve.evaluate(0.75, highlight: -2, shadow: 0), 0.724982211387, accuracy: 1e-9)
        XCTAssertEqual(ToneCurve.evaluate(0.25, highlight: 0, shadow: -2), 0.299342958294, accuracy: 1e-9)
        XCTAssertEqual(ToneCurve.evaluate(0.8, highlight: 2, shadow: 3), 0.828519484754, accuracy: 1e-9)
    }
}

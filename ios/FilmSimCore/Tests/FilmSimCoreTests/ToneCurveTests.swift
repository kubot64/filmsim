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
}

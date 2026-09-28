import XCTest
@testable import FilmSimCore

final class ExposureCompensationTests: XCTestCase {
    func testDialCoversPlusMinusThreeInThirds() {
        XCTAssertEqual(ExposureCompensation.dialThirds.count, 19)
        XCTAssertEqual(ExposureCompensation.dialThirds.first, -9)
        XCTAssertEqual(ExposureCompensation.dialThirds.last, 9)
    }

    func testThirdsRoundTrip() {
        for t in ExposureCompensation.dialThirds {
            XCTAssertEqual(ExposureCompensation.thirds(ExposureCompensation.ev(thirds: t)), t)
        }
        XCTAssertEqual(ExposureCompensation.thirds(-0.33), -1)
        XCTAssertEqual(ExposureCompensation.thirds(0.67), 2)
    }

    private let iPhoneRange: ClosedRange<Float> = -8...8

    func testStepsAreThirdsOfAStop() {
        var ev: Float = 0
        ev = ExposureCompensation.stepped(ev, by: -1, deviceRange: iPhoneRange)
        XCTAssertEqual(ev, -1.0 / 3.0, accuracy: 1e-6)
        ev = ExposureCompensation.stepped(ev, by: -2, deviceRange: iPhoneRange)
        XCTAssertEqual(ev, -1, accuracy: 1e-6)
    }

    /// Float drift after many steps must not move the value off the 1/3 grid.
    func testRepeatedStepsStayOnTheGrid() {
        var ev: Float = 0
        for _ in 0..<7 { ev = ExposureCompensation.stepped(ev, by: 1, deviceRange: iPhoneRange) }
        for _ in 0..<7 { ev = ExposureCompensation.stepped(ev, by: -1, deviceRange: iPhoneRange) }
        XCTAssertEqual(ev, 0)
    }

    func testClampsToThreeStopsAndToTheDevice() {
        XCTAssertEqual(ExposureCompensation.stepped(3, by: 1, deviceRange: iPhoneRange), 3)
        XCTAssertEqual(ExposureCompensation.stepped(-3, by: -1, deviceRange: iPhoneRange), -3)
        XCTAssertEqual(ExposureCompensation.stepped(1, by: 3, deviceRange: -2...2), 2)
    }

    func testLabels() {
        XCTAssertEqual(ExposureCompensation.label(0), "±0")
        XCTAssertEqual(ExposureCompensation.label(1.0 / 3.0), "+⅓")
        XCTAssertEqual(ExposureCompensation.label(-2.0 / 3.0), "−⅔")
        XCTAssertEqual(ExposureCompensation.label(1), "+1")
        XCTAssertEqual(ExposureCompensation.label(-4.0 / 3.0), "−1⅓")
        XCTAssertEqual(ExposureCompensation.label(3), "+3")
    }
}

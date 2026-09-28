import XCTest
@testable import FilmSimCore

final class HoldingOrientationTests: XCTestCase {
    func testUprightNeedsNoTurn() {
        XCTAssertEqual(HoldingOrientation.controlRotation(captureAngle: 90), 0)
        XCTAssertFalse(HoldingOrientation.isSideways(0))
    }

    /// Top of the phone to the left: the screen has turned 90° anticlockwise, so the controls turn clockwise.
    func testTopToTheLeftTurnsClockwise() {
        XCTAssertEqual(HoldingOrientation.controlRotation(captureAngle: 0), 90)
        XCTAssertTrue(HoldingOrientation.isSideways(90))
    }

    func testTopToTheRightTurnsAnticlockwise() {
        XCTAssertEqual(HoldingOrientation.controlRotation(captureAngle: 180), -90)
        XCTAssertTrue(HoldingOrientation.isSideways(-90))
    }

    func testUpsideDownKeepsTheUprightLayout() {
        XCTAssertEqual(HoldingOrientation.controlRotation(captureAngle: 270), 0)
    }

    func testFullTurnIsTheSameAsNone() {
        XCTAssertEqual(HoldingOrientation.controlRotation(captureAngle: 450), 0)
    }
}

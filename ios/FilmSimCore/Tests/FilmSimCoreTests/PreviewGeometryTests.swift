import CoreGraphics
import XCTest
@testable import FilmSimCore

final class PreviewGeometryTests: XCTestCase {
    /// 24mm on a 4:3 sensor keeps the full width and 8/9 of the height (3:2 of a 4:3 frame).
    func testTwentyFourMillimetreCropOnFourByThree() {
        let c = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm24)
        XCTAssertEqual(c.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(c.width, 1, accuracy: 1e-9)
        XCTAssertEqual(c.height, 8.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(c.midY, 0.5, accuracy: 1e-9)
    }

    /// Longer focal lengths shrink the crop by 24/f around the centre.
    func testCropShrinksByTwentyFourOverFocal() {
        for focal in FocalLength.allCases {
            let c = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: focal)
            XCTAssertEqual(c.width, 24 / focal.millimeters, accuracy: 1e-9, focal.displayName)
            XCTAssertEqual(c.midX, 0.5, accuracy: 1e-9)
            XCTAssertEqual(c.midY, 0.5, accuracy: 1e-9)
        }
    }

    func testUnknownAspectUsesFourByThree() {
        XCTAssertEqual(
            PreviewGeometry.crop(sensorAspect: 0, focalLength: .mm35),
            PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm35)
        )
    }

    /// Clockwise turn: the preview's top-left is the sensor's bottom-left, its top-right the sensor's top-left.
    func testCornersFollowAClockwiseTurn() {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        assertPoint(PreviewGeometry.devicePoint(fromView: CGPoint(x: 0, y: 0), crop: full), CGPoint(x: 0, y: 1))
        assertPoint(PreviewGeometry.devicePoint(fromView: CGPoint(x: 1, y: 0), crop: full), CGPoint(x: 0, y: 0))
        assertPoint(PreviewGeometry.devicePoint(fromView: CGPoint(x: 1, y: 1), crop: full), CGPoint(x: 1, y: 0))
        assertPoint(PreviewGeometry.devicePoint(fromView: CGPoint(x: 0.5, y: 0.5), crop: full), CGPoint(x: 0.5, y: 0.5))
    }

    func testViewPointInvertsDevicePoint() {
        for focal in FocalLength.allCases {
            let c = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: focal)
            for p in [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.7), CGPoint(x: 0.5, y: 0.5)] {
                let d = PreviewGeometry.devicePoint(fromView: p, crop: c)
                assertPoint(PreviewGeometry.viewPoint(fromDevice: d, crop: c), p)
            }
        }
    }

    /// A device point picked at 24mm stays on the same subject at 35mm, so it moves outward in the view.
    func testSameDevicePointMovesOutwardAtLongerFocal() {
        let wide = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm24)
        let tele = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm35)
        let d = PreviewGeometry.devicePoint(fromView: CGPoint(x: 0.6, y: 0.4), crop: wide)
        let v = PreviewGeometry.viewPoint(fromDevice: d, crop: tele)
        XCTAssertGreaterThan(v.x, 0.6)
        XCTAssertLessThan(v.y, 0.4)
    }

    /// A point at the edge of the 24mm frame is outside the 35mm crop; it moves to just inside.
    func testClampedMovesAnEdgePointInsideALongerCrop() {
        let wide = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm24)
        let tele = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm35)
        let edge = PreviewGeometry.devicePoint(fromView: CGPoint(x: 0.02, y: 0.98), crop: wide)
        let c = PreviewGeometry.clamped(edge, into: tele)
        let v = PreviewGeometry.viewPoint(fromDevice: c, crop: tele)
        XCTAssertEqual(v.x, 0.05, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.95, accuracy: 1e-9)
    }

    func testClampedKeepsAPointInside() {
        let tele = PreviewGeometry.crop(sensorAspect: 4.0 / 3.0, focalLength: .mm35)
        assertPoint(PreviewGeometry.clamped(CGPoint(x: 0.5, y: 0.45), into: tele), CGPoint(x: 0.5, y: 0.45))
    }

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }
}

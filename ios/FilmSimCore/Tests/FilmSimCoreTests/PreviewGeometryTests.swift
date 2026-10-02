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

    // MARK: Tap → focus point

    func testImageRectFillsATwoByThreeView() {
        let r = PreviewGeometry.imageRect(in: CGRect(x: 0, y: 0, width: 400, height: 600))
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 400, height: 600))
    }

    /// A taller view than 2:3 fills the height and crops the sides.
    func testImageRectAspectFillsATallView() {
        let r = PreviewGeometry.imageRect(in: CGRect(x: 0, y: 0, width: 400, height: 900))
        XCTAssertEqual(r.height, 900, accuracy: 1e-9)
        XCTAssertEqual(r.width, 600, accuracy: 1e-9)
        XCTAssertEqual(r.midX, 200, accuracy: 1e-9)
    }

    func testCentreTapFocusesOnTheCentre() {
        let p = PreviewGeometry.focusViewPoint(
            forTap: CGPoint(x: 200, y: 300), in: CGRect(x: 0, y: 0, width: 400, height: 600),
            frameSize: CGSize(width: 72, height: 72)
        )
        assertPoint(p!, CGPoint(x: 0.5, y: 0.5))
    }

    /// A tap in a corner moves in by half the frame, so the whole frame is on screen.
    func testCornerTapMovesInByHalfTheFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        let p = PreviewGeometry.focusViewPoint(
            forTap: CGPoint(x: 2, y: 598), in: bounds, frameSize: CGSize(width: 72, height: 72))
        assertPoint(p!, CGPoint(x: 36.0 / 400, y: (600 - 36.0) / 600))
    }

    /// When the image sticks out of a tall view, the frame stays inside the view, not the image.
    func testEdgeTapStaysInsideTheViewWhenTheImageSticksOut() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 900)
        let image = PreviewGeometry.imageRect(in: bounds)
        let p = PreviewGeometry.focusViewPoint(
            forTap: CGPoint(x: 0, y: 450), in: bounds, frameSize: CGSize(width: 72, height: 72))!
        XCTAssertEqual(image.minX + p.x * image.width, 36, accuracy: 1e-9)
    }

    func testNoFocusPointForAnEmptyView() {
        XCTAssertNil(PreviewGeometry.focusViewPoint(forTap: .zero, in: .zero, frameSize: CGSize(width: 72, height: 72)))
    }

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }
}

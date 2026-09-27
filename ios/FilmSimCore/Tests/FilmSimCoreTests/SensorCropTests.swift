import CoreImage
import ImageIO
import XCTest
@testable import FilmSimCore

final class SensorCropTests: XCTestCase {
    func test35mmCropOf48MP() {
        let extent = CGRect(x: 0, y: 0, width: 8064, height: 6048)
        let r = SensorCrop.rectThreeByTwo(in: extent, focalLength: .mm35)
        XCTAssertEqual(r.width, CGFloat(8064) * 24 / 35, accuracy: 1e-6)
        XCTAssertEqual(r.height, r.width * 2 / 3, accuracy: 1e-6)
        XCTAssertEqual(r.midX, extent.midX, accuracy: 1e-6)
        XCTAssertEqual(r.midY, extent.midY, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(r.minX, 0)
        XCTAssertGreaterThanOrEqual(r.minY, 0)
        XCTAssertLessThanOrEqual(r.maxX, extent.maxX + 1e-6)
        XCTAssertLessThanOrEqual(r.maxY, extent.maxY + 1e-6)
    }

    func testCropShrinksToFitShortFrame() {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let r = SensorCrop.rectThreeByTwo(in: extent, focalLength: .mm35)
        XCTAssertEqual(r.height, CGFloat(400), accuracy: 1e-6)
        XCTAssertEqual(r.width, CGFloat(600), accuracy: 1e-6)
        XCTAssertEqual(r.midX, extent.midX, accuracy: 1e-6)
    }

    /// 12MP 4:3 main camera: 24mm keeps the full width, 28mm keeps 24/28 of it.
    func testWiderFocalLengthsOf12MP() {
        let extent = CGRect(x: 0, y: 0, width: 4032, height: 3024)
        let r24 = SensorCrop.rectThreeByTwo(in: extent, focalLength: .mm24)
        XCTAssertEqual(r24.width, 4032, accuracy: 1e-6)
        XCTAssertEqual(r24.height, 2688, accuracy: 1e-6)
        let r28 = SensorCrop.rectThreeByTwo(in: extent, focalLength: .mm28)
        XCTAssertEqual(r28.width, CGFloat(4032) * 24 / 28, accuracy: 1e-6)
        XCTAssertEqual(r28.height, r28.width * 2 / 3, accuracy: 1e-6)
        XCTAssertEqual(r28.midX, extent.midX, accuracy: 1e-6)
        XCTAssertEqual(r28.midY, extent.midY, accuracy: 1e-6)
    }

    func testPortraitShotKeeps35mmOnTheSensorLongSide() {
        let native = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8064, height: 6048))
        let upright = native.croppedThreeByTwo(focalLength: .mm35, shot: .up)
        let portrait = native.croppedThreeByTwo(focalLength: .mm35, shot: .right)
        XCTAssertEqual(upright.extent.width / 8064, CGFloat(24.0 / 35.0), accuracy: 0.001)
        XCTAssertGreaterThan(upright.extent.width, upright.extent.height)
        XCTAssertEqual(portrait.extent.width, upright.extent.height, accuracy: 0.5)
        XCTAssertEqual(portrait.extent.height, upright.extent.width, accuracy: 0.5)
    }
}

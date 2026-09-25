import CoreImage
import ImageIO
import XCTest
@testable import FilmSimCore

final class SensorCropTests: XCTestCase {
    func test35mmCropOf48MP() {
        let extent = CGRect(x: 0, y: 0, width: 8064, height: 6048)
        let r = SensorCrop.rect35mmThreeByTwo(in: extent)
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
        let r = SensorCrop.rect35mmThreeByTwo(in: extent)
        XCTAssertEqual(r.height, CGFloat(400), accuracy: 1e-6)
        XCTAssertEqual(r.width, CGFloat(600), accuracy: 1e-6)
        XCTAssertEqual(r.midX, extent.midX, accuracy: 1e-6)
    }

    func testPortraitShotKeeps35mmOnTheSensorLongSide() {
        let native = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 8064, height: 6048))
        let upright = native.cropped35mmThreeByTwo(shot: .up)
        let portrait = native.cropped35mmThreeByTwo(shot: .right)
        XCTAssertEqual(upright.extent.width / 8064, CGFloat(24.0 / 35.0), accuracy: 0.001)
        XCTAssertGreaterThan(upright.extent.width, upright.extent.height)
        XCTAssertEqual(portrait.extent.width, upright.extent.height, accuracy: 0.5)
        XCTAssertEqual(portrait.extent.height, upright.extent.width, accuracy: 0.5)
    }
}

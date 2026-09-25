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

    func testPreviewZoomForFourByThree() {
        XCTAssertEqual(SensorCrop.previewZoom(videoAspectWidthOverHeight: 4.0 / 3.0), 35.0 / 24.0, accuracy: 1e-9)
    }

    func testPreviewZoomForSixteenByNine() {
        XCTAssertEqual(SensorCrop.previewZoom(videoAspectWidthOverHeight: 16.0 / 9.0), 1.23046875, accuracy: 1e-9)
    }
}

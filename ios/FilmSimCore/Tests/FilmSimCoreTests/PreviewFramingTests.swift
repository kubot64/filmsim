import XCTest
@testable import FilmSimCore

final class PreviewFramingTests: XCTestCase {
    /// A 4:3 sensor rotated 90° into a portrait 2:3 view needs exactly focal/24 of zoom:
    /// 1 at 24mm, 28/24 and 35/24 for the crops.
    func testFourByThreeSensorInPortraitTwoByThreeZoomsByFocalOver24() {
        for focal in FocalLength.allCases {
            XCTAssertEqual(
                PreviewFraming.zoom(sensorAspectWidthOverHeight: PreviewFraming.defaultSensorAspect, focalLength: focal),
                focal.millimeters / 24,
                accuracy: 1e-9,
                focal.displayName
            )
        }
    }

    func testUnknownAspectFallsBackToFocalOver24() {
        XCTAssertEqual(PreviewFraming.zoom(sensorAspectWidthOverHeight: 0, focalLength: .mm35), 35.0 / 24.0, accuracy: 1e-9)
    }
}

import XCTest
@testable import FilmSimCore

final class PreviewFramingTests: XCTestCase {
    /// A 4:3 sensor rotated 90° into a portrait 2:3 view needs exactly the 35/24 crop zoom.
    func testFourByThreeSensorInPortraitTwoByThreeZoomsBy35Over24() {
        let ratio = SensorCrop.targetEquivalentMM / SensorCrop.wideEquivalentMM
        XCTAssertEqual(ratio, 35.0 / 24.0)
        XCTAssertEqual(Double(PreviewFraming.defaultZoom), ratio)
        XCTAssertEqual(
            PreviewFraming.zoom(sensorAspectWidthOverHeight: 4.0 / 3.0),
            ratio,
            accuracy: 1e-9
        )
    }
}

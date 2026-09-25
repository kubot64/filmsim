import XCTest
@testable import FilmSimCore

final class GrainTests: XCTestCase {
    func testWeightMatchesPython() {
        XCTAssertEqual(Grain.weight(luminance: 0), 0)
        XCTAssertEqual(Grain.weight(luminance: 1), 0)
        XCTAssertEqual(Grain.weight(luminance: 0.25), 0.75, accuracy: 1e-12)
        XCTAssertGreaterThan(Grain.weight(luminance: 0.4), Grain.weight(luminance: 0.02))
        XCTAssertGreaterThan(Grain.weight(luminance: 0.4), Grain.weight(luminance: 0.98))
    }

    func testUnitNoiseGainMatchesScipyKernel() {
        // scipy.ndimage.gaussian_filter, truncate=4, separable, on uniform[-0.5, 0.5].
        XCTAssertEqual(Grain.unitNoiseGain(sigma: 0.6), 6.991621, accuracy: 1e-4)
        XCTAssertEqual(Grain.unitNoiseGain(sigma: 1.1), 13.507091, accuracy: 1e-4)
    }
}

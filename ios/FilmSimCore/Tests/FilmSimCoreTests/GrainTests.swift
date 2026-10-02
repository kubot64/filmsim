import XCTest

@testable import FilmSimCore

final class GrainTests: XCTestCase {
    func testUnitNoiseGainMatchesScipyKernel() {
        // scipy.ndimage.gaussian_filter, truncate=4, separable, on uniform[-0.5, 0.5].
        XCTAssertEqual(Grain.unitNoiseGain(sigma: 0.6), 6.991621, accuracy: 1e-4)
        XCTAssertEqual(Grain.unitNoiseGain(sigma: 1.1), 13.507091, accuracy: 1e-4)
    }
}

import XCTest
import simd
@testable import FilmSimCore

final class GamutTests: XCTestCase {
    func testBT709ToXYZMatchesKnownValues() {
        let m = RGBSpace.bt709.toXYZ
        XCTAssertEqual(m[0, 0], 0.4124, accuracy: 2e-4) // column 0 = R
        XCTAssertEqual(m[0, 1], 0.2126, accuracy: 2e-4)
        XCTAssertEqual(m[1, 1], 0.7152, accuracy: 2e-4)
        XCTAssertEqual(m[2, 2], 0.9505, accuracy: 2e-4)
    }

    func testWhitePreservedP3ToFGamut() {
        let w = RGBSpace.conversion(from: .displayP3, to: .fGamut) * SIMD3<Double>(1, 1, 1)
        XCTAssertEqual(w.x, 1, accuracy: 1e-9)
        XCTAssertEqual(w.y, 1, accuracy: 1e-9)
        XCTAssertEqual(w.z, 1, accuracy: 1e-9)
    }
}

import XCTest
import simd
@testable import FilmSimCore

final class ColorMatrixTests: XCTestCase {
    func testRedContributionIsScaledColumn() {
        let m = RGBSpace.bt709.toXYZ
        let v = ColorMatrix.contributions(m, gains: SIMD3(2, 3, 4))
        // Known BT.709 → XYZ columns, so a transposed matrix fails this.
        XCTAssertEqual(v.r.x, 0.4124 * 2, accuracy: 2e-4)
        XCTAssertEqual(v.r.y, 0.2126 * 2, accuracy: 2e-4)
        XCTAssertEqual(v.g.y, 0.7152 * 3, accuracy: 2e-4)
        XCTAssertEqual(v.b.z, 0.9505 * 4, accuracy: 2e-4)
    }

    func testPremultipliedGainsMatchMatrixVectorProduct() {
        let m = RGBSpace.conversion(from: .displayP3, to: .fGamut)
        let gains = SIMD3<Double>(1.2, 1.0, 0.8)
        let v = ColorMatrix.contributions(m, gains: gains)
        let rgb = SIMD3<Double>(0.2, 0.3, 0.4)
        let expected = m * (rgb * gains)
        let got = v.r * rgb.x + v.g * rgb.y + v.b * rgb.z
        XCTAssertEqual(got.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(got.y, expected.y, accuracy: 1e-12)
        XCTAssertEqual(got.z, expected.z, accuracy: 1e-12)
    }
}

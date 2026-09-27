import simd
import XCTest
@testable import FilmSimCore

final class LUTInputTests: XCTestCase {
    private func identity(_ n: Int) -> CubeLUT {
        var floats: [Float] = []
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            floats += [Float(r), Float(g), Float(b)].map { $0 / Float(n - 1) } + [1]
        } } }
        return CubeLUT(title: "identity", size: n, floats: floats)
    }

    func testSLog3MatchesSonyReferencePoints() {
        XCTAssertEqual(SLog3.encode(0), 95.0 / 1023, accuracy: 1e-6)
        XCTAssertEqual(SLog3.encode(0.18), 420.0 / 1023, accuracy: 1e-6)
        XCTAssertEqual(SLog3.encode(0.90), 598.0 / 1023, accuracy: 0.5 / 1023)
        for x in [0.0, 0.005, 0.01125, 0.18, 0.9, 5.0] {
            XCTAssertEqual(SLog3.decode(SLog3.encode(x)), x, accuracy: 1e-9)
        }
    }

    func testSonyGamutsKeepWhite() {
        for space in [RGBSpace.sGamut3, .sGamut3Cine] {
            let w = RGBSpace.conversion(from: .fGamut, to: space) * SIMD3<Double>(repeating: 1)
            XCTAssertEqual(w.x, 1, accuracy: 1e-9)
            XCTAssertEqual(w.y, 1, accuracy: 1e-9)
            XCTAssertEqual(w.z, 1, accuracy: 1e-9)
        }
    }

    func testFLog2MidGreyLandsOnSLog3MidGrey() {
        let grey = SIMD3<Double>(repeating: FLog2.encode(0.18))
        for input in [LUTInput.sLog3SGamut3Cine, .sLog3SGamut3] {
            let s = input.codes(fromFLog2: grey)
            XCTAssertEqual(s.x, 420.0 / 1023, accuracy: 1e-6)
            XCTAssertEqual(s.y, s.x, accuracy: 1e-9)
            XCTAssertEqual(s.z, s.x, accuracy: 1e-9)
        }
        XCTAssertEqual(LUTInput.fLog2.codes(fromFLog2: grey), grey)
    }

    /// Converting a LUT that returns its input shows exactly which S-Log3 code each F-Log2 node reads.
    func testConvertedLUTLooksUpTheSLog3Codes() {
        let converted = identity(33).convertedToFLog2(from: .sLog3SGamut3Cine, size: 9)
        XCTAssertEqual(converted.size, 9)
        for (r, g, b) in [(0, 0, 0), (4, 4, 4), (8, 2, 5), (3, 7, 1)] {
            let code = SIMD3(Double(r), Double(g), Double(b)) / 8
            let expected = simd_clamp(LUTInput.sLog3SGamut3Cine.codes(fromFLog2: code), SIMD3(repeating: 0), SIMD3(repeating: 1))
            let (x, y, z) = converted.node(r: r, g: g, b: b)
            XCTAssertEqual(Double(x), expected.x, accuracy: 1e-5)
            XCTAssertEqual(Double(y), expected.y, accuracy: 1e-5)
            XCTAssertEqual(Double(z), expected.z, accuracy: 1e-5)
        }
    }

    func testFLog2InputIsLeftAlone() {
        let lut = identity(5)
        XCTAssertEqual(lut.convertedToFLog2(from: .fLog2).rgbaData, lut.rgbaData)
    }

    func testCubeTextRoundTrips() throws {
        let lut = identity(5).convertedToFLog2(from: .sLog3SGamut3, size: 5)
        let back = try CubeLUT(text: lut.cubeText)
        XCTAssertEqual(back.size, 5)
        let a = lut.node(r: 3, g: 1, b: 4), c = back.node(r: 3, g: 1, b: 4)
        XCTAssertEqual(a.0, c.0, accuracy: 1e-6)
        XCTAssertEqual(a.1, c.1, accuracy: 1e-6)
        XCTAssertEqual(a.2, c.2, accuracy: 1e-6)
    }
}

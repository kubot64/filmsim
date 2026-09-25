import XCTest
@testable import FilmSimCore

final class CubeLUTTests: XCTestCase {
    func testParseSwapLUT() throws {
        var lines = ["TITLE \"swap\"", "LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(b) \(g) \(r)") } } }
        let lut = try CubeLUT(text: lines.joined(separator: "\n"))
        XCTAssertEqual(lut.title, "swap")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.rgbaData.count, 8 * 4 * MemoryLayout<Float>.size)
        let n = lut.node(r: 1, g: 0, b: 0)
        XCTAssertEqual(n.0, 0); XCTAssertEqual(n.1, 0); XCTAssertEqual(n.2, 1)
    }

    func testRejectsWrongRowCount() {
        XCTAssertThrowsError(try CubeLUT(text: "LUT_3D_SIZE 2\n0 0 0\n"))
    }
}

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

    /// Imported files can be anything. Each of these must be an error, never a crash.
    private func unitRows(_ n: Int) -> String {
        (0..<(n * n * n)).map { _ in "0.5 0.5 0.5" }.joined(separator: "\n")
    }

    private func error(_ text: String) -> CubeLUT.ParseError? {
        do { _ = try CubeLUT(text: text); return nil } catch { return error as? CubeLUT.ParseError }
    }

    func testRejectsBrokenSizeLines() {
        XCTAssertEqual(error("LUT_3D_SIZE\n0 0 0\n"), .badSize("LUT_3D_SIZE"))
        XCTAssertNotNil(error("LUT_3D_SIZE two\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE 0\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE 1\n0 0 0\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE -2\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE 3000000\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE 99999999999999999999999\n"))
        XCTAssertNotNil(error("LUT_3D_SIZE 2\nLUT_3D_SIZE 3\n" + unitRows(2)))
        XCTAssertEqual(error(unitRows(2)), .missingSize)
    }

    func testRejectsValuesThatAreNotColours() {
        for bad in ["nan", "inf", "-inf", "1e30"] {
            let rows = unitRows(2).replacingOccurrences(of: "0.5 0.5 0.5\n", with: "\(bad) 0.5 0.5\n", options: .anchored)
            XCTAssertNotNil(error("LUT_3D_SIZE 2\n" + rows), bad)
        }
        XCTAssertNoThrow(try CubeLUT(text: "LUT_3D_SIZE 2\n" + unitRows(2).replacingOccurrences(of: "0.5", with: "1.25")))
    }

    func testOnlyTheDefaultDomainIsRead() {
        let body = "LUT_3D_SIZE 2\n" + unitRows(2)
        XCTAssertNoThrow(try CubeLUT(text: "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 1.0 1.0 1.0\n" + body))
        XCTAssertNoThrow(try CubeLUT(text: "LUT_3D_INPUT_RANGE 0.0 1.0\n" + body))
        XCTAssertEqual(error("DOMAIN_MAX 1.5 2 3\n" + body), .unsupportedDomain)
        XCTAssertEqual(error("DOMAIN_MIN\n" + body), .unsupportedDomain)
        XCTAssertEqual(error("LUT_3D_INPUT_RANGE -0.1 1.2\n" + body), .unsupportedDomain)
    }

    func testStopsAtTooManyRowsInsteadOfFillingMemory() {
        XCTAssertEqual(error("LUT_3D_SIZE 2\n" + unitRows(3)), .badRowCount(expected: 8, got: 9))
    }

    func testRejectsHugeOrNonTextFiles() {
        XCTAssertEqual(try? CubeLUT(data: Data(count: CubeLUT.maxFileBytes + 1)).size, nil)
        XCTAssertThrowsError(try CubeLUT(data: Data([0xFF, 0xFE, 0x00, 0xD8])))
        let tooLong = String(repeating: "#", count: CubeLUT.maxFileBytes + 1)
        XCTAssertEqual(error(tooLong), .tooLarge)
    }

    func testOddButHarmlessLinesAreSkipped() throws {
        let lut = try CubeLUT(text: "\n   \n# c\nTITLE\nLUT_3D_SIZE\t2\n\t\n" + unitRows(2))
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.title, "")
    }
}

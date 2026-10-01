import XCTest

@testable import FilmSimCore

final class LUTInputDetectionTests: XCTestCase {
    private func detect(_ fileName: String, _ header: String = "") -> LUTInputDetection.Result {
        LUTInputDetection.detect(fileName: fileName, cubeText: header + "LUT_3D_SIZE 2\n0 0 0\n")
    }

    private func isRefused(_ result: LUTInputDetection.Result) -> Bool {
        if case .unsupported = result { return true }
        return false
    }

    func testFujifilmOfficialNames() {
        XCTAssertEqual(detect("FLog2_to_PROVIA_65grid_V.1.00.cube"), .supported(.fLog2))
        XCTAssertEqual(detect("FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube"), .supported(.fLog2))
        XCTAssertEqual(detect("F-Log2 Classic Film.cube"), .supported(.fLog2))
    }

    func testSonyNames() {
        XCTAssertEqual(detect("SLog3SGamut3.CineToLC-709_.cube"), .supported(.sLog3SGamut3Cine))
        XCTAssertEqual(detect("slog3_sgamut3cine_portra.cube"), .supported(.sLog3SGamut3Cine))
        XCTAssertEqual(detect("S-Log3_S-Gamut3_Kodak.cube"), .supported(.sLog3SGamut3))
    }

    func testTitleOrCommentCounts() {
        XCTAssertEqual(
            detect("warm.cube", "TITLE \"Warm look for S-Log3 / S-Gamut3.Cine\"\n"), .supported(.sLog3SGamut3Cine))
        XCTAssertEqual(detect("warm.cube", "# Input: F-Log2\n"), .supported(.fLog2))
    }

    func testUnclearOrUnsupportedIsRefused() {
        XCTAssertTrue(isRefused(detect("MyLook_SLog3.cube")))  // gamut unknown
        XCTAssertTrue(isRefused(detect("SLog3_to_FLog2.cube")))  // both
        XCTAssertTrue(isRefused(detect("FLog2C_to_ETERNA.cube")))  // F-Log2 C, different gamut
        XCTAssertTrue(isRefused(detect("F-Log2 C Look.cube")))
        XCTAssertTrue(isRefused(detect("FLog_to_WDR_BT.709.cube")))  // first F-Log
        XCTAssertTrue(isRefused(detect("VLog_to_V709.cube")))
        XCTAssertTrue(isRefused(detect("Portra400.cube")))  // says nothing
    }

    /// Only the header is read: numbers in the table must not be mistaken for anything.
    func testTableIsNotScanned() {
        XCTAssertEqual(
            LUTInputDetection.headerLines(of: "TITLE \"x\"\n# c\nLUT_3D_SIZE 2\n0.1 0.2 0.3\n"), ["TITLE \"x\"", "# c"])
    }
}

import XCTest
@testable import FilmSimCore

final class FLog2Tests: XCTestCase {
    func testDatasheetReferencePoints() {
        XCTAssertEqual(FLog2.encode(0.00) * 1023, 95, accuracy: 1.0)
        XCTAssertEqual(FLog2.encode(0.18) * 1023, 400, accuracy: 1.0)
        XCTAssertEqual(FLog2.encode(0.90) * 1023, 570, accuracy: 1.0)
    }

    func testRoundTrip() {
        for x in stride(from: 0.0001, through: 8.0, by: 0.05) {
            XCTAssertEqual(FLog2.decode(FLog2.encode(x)), x, accuracy: 1e-6)
        }
    }
}

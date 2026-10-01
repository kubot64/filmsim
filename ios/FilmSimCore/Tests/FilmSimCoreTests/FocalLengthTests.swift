import XCTest

@testable import FilmSimCore

final class FocalLengthTests: XCTestCase {
    func testNextStepsThroughAndWraps() {
        XCTAssertEqual(FocalLength.mm24.next, .mm28)
        XCTAssertEqual(FocalLength.mm28.next, .mm35)
        XCTAssertEqual(FocalLength.mm35.next, .mm24)
    }

    func testStoredFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "FocalLengthTests")!
        defaults.removePersistentDomain(forName: "FocalLengthTests")
        XCTAssertEqual(FocalLength.stored(in: defaults), .mm35)
        defaults.set(50, forKey: FocalLength.storageKey)
        XCTAssertEqual(FocalLength.stored(in: defaults), .mm35)
        defaults.set(28, forKey: FocalLength.storageKey)
        XCTAssertEqual(FocalLength.stored(in: defaults), .mm28)
    }
}

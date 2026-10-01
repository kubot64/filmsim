import XCTest
@testable import FilmSimCore

final class FocusSettlingTests: XCTestCase {
    /// A refocus seen on the iPhone 15 Pro Max: 0.0 to about 0.21 in 1/255 steps, then still.
    func testSettlesOnceAfterARefocus() {
        var s = FocusSettling()
        for p: Float in [0.0, 0.027, 0.051, 0.098, 0.137, 0.173, 0.196, 0.204, 0.208] { s.lensMoved(to: p) }
        XCTAssertTrue(s.lensStopped(at: 0.208))
        XCTAssertFalse(s.lensStopped(at: 0.208))
    }

    /// While resting the lens wobbles by a step (0.204 to 0.208). That is not a refocus.
    func testRestingWobbleDoesNotCount() {
        var s = FocusSettling()
        s.lensMoved(to: 0.208)
        XCTAssertFalse(s.lensStopped(at: 0.208))
        s.lensMoved(to: 0.204)
        s.lensMoved(to: 0.208)
        XCTAssertFalse(s.lensStopped(at: 0.208))
    }

    /// Travel is measured from where the lens rested, so slow small steps still add up.
    func testSmallStepsAddUpFromTheRestingPlace() {
        var s = FocusSettling()
        s.lensMoved(to: 0.5)
        _ = s.lensStopped(at: 0.5)
        for p: Float in [0.505, 0.51, 0.515, 0.52, 0.525] { s.lensMoved(to: p) }
        XCTAssertTrue(s.lensStopped(at: 0.525))
    }

    /// Going out and back to the same place is still a refocus.
    func testThereAndBackCounts() {
        var s = FocusSettling()
        s.lensMoved(to: 0.3)
        _ = s.lensStopped(at: 0.3)
        for p: Float in [0.35, 0.4, 0.35, 0.3] { s.lensMoved(to: p) }
        XCTAssertTrue(s.lensStopped(at: 0.3))
    }
}

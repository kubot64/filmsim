import XCTest

@testable import FilmSimCore

final class FocusSettlingTests: XCTestCase {
    /// A refocus logged on the iPhone 15 Pro Max: big steps to 0.196, then 1/255 steps to 0.208.
    func testCreepingInDoesNotDelayTheSettle() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.0)
        let big = [0.027, 0.051, 0.071, 0.098, 0.114, 0.137, 0.157, 0.173, 0.184, 0.196].map {
            s.lensMoved(to: Float($0))
        }
        XCTAssertEqual(big, Array(repeating: true, count: big.count))
        let creep = [0.200, 0.204, 0.208].map { s.lensMoved(to: Float($0)) }
        XCTAssertEqual(creep, [false, false, false])
        XCTAssertTrue(s.lensStopped())
        XCTAssertFalse(s.lensStopped())
    }

    /// While resting the lens wobbles by a step (0.204 to 0.208). That is not a refocus.
    func testRestingWobbleDoesNotCount() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.208)
        XCTAssertFalse(s.lensMoved(to: 0.204))
        XCTAssertFalse(s.lensMoved(to: 0.208))
        XCTAssertFalse(s.lensStopped())
    }

    /// Travel is measured from where the lens rested, so a slow creep still adds up.
    func testSlowCreepAddsUpFromTheRestingPlace() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.5)
        _ = s.lensStopped()
        for p: Float in [0.504, 0.508, 0.512, 0.516, 0.520, 0.524] { _ = s.lensMoved(to: p) }
        XCTAssertTrue(s.lensStopped())
    }

    /// What the screen does with a creep alone: no step restarts the wait, so a wait ends every
    /// 0.1 s, about every 3 reports of 1/255. The travel must carry over those waits.
    func testCreepAcrossSeveralWaitsCounts() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.5)
        _ = s.lensStopped()
        var settled: [Bool] = []
        var p: Float = 0.5
        for _ in 0..<3 {
            for _ in 0..<3 {
                p += 1 / 255
                XCTAssertFalse(s.lensMoved(to: p))
            }
            settled.append(s.lensStopped())
        }
        // 3/255 is short of minimumTravel; 6/255 (0.024) passes it in the second wait.
        XCTAssertEqual(settled, [false, true, false])
        XCTAssertFalse(s.lensStopped())
    }

    /// Going out and back to the same place is still a refocus.
    func testThereAndBackCounts() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.3)
        _ = s.lensStopped()
        for p: Float in [0.35, 0.4, 0.35, 0.3] { _ = s.lensMoved(to: p) }
        XCTAssertTrue(s.lensStopped())
    }

    /// The next refocus is measured from where the last one ended, not from the first report.
    func testRestsWhereTheLensStopped() {
        var s = FocusSettling()
        _ = s.lensMoved(to: 0.1)
        _ = s.lensMoved(to: 0.3)
        XCTAssertTrue(s.lensStopped())
        _ = s.lensMoved(to: 0.31)
        XCTAssertFalse(s.lensStopped())
    }
}

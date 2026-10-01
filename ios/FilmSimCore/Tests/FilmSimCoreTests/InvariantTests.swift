import XCTest
@testable import FilmSimCore

/// Property tests: each rule must hold for every input, so each test throws thousands of
/// random inputs at it instead of a few hand-picked ones. Each test's seed is fixed in the
/// source, so a failure reproduces exactly, and its message names the failing input.
final class InvariantTests: XCTestCase {
    private let cases = 5_000

    // MARK: - FLog2

    /// The datasheet's six-digit constants leave the linear piece 3.5e-8 above the log piece at
    /// cut1. Codes in that sliver decode through the log piece, so x just below cut1 comes back
    /// about 4e-9 off. Far below one 16-bit step (1.5e-5), but it bounds what "exact" can mean.
    private let seamStep = FLog2.e * FLog2.cut1 + FLog2.f - FLog2.encode(FLog2.cut1)

    /// INV-FLOG2-1: decode(encode(x)) == x for any scene-linear x the camera can see.
    func testFLog2RoundTripsEverywhere() {
        var rng = SplitMix64(seed: 1)
        let edges = [0, FLog2.cut1, FLog2.cut1.nextDown, 0.18, 0.90, 16]
        for x in edges + (0..<cases).map({ _ in Double.random(in: 0...16, using: &rng) }) {
            XCTAssertEqual(FLog2.decode(FLog2.encode(x)), x, accuracy: 1e-8, "x=\(x)")
        }
    }

    /// INV-FLOG2-2: brighter in, brighter out. A dip would reverse a gradient in the LUT.
    /// Each piece is strictly increasing; across cut1 the only drop is `seamStep`.
    func testFLog2IsStrictlyIncreasing() {
        var rng = SplitMix64(seed: 2)
        for _ in 0..<cases {
            let a = Double.random(in: 0...16, using: &rng)
            let b = Double.random(in: 0...16, using: &rng)
            guard a != b else { continue }
            let (lo, hi) = (min(a, b), max(a, b))
            if (lo < FLog2.cut1) == (hi < FLog2.cut1) {
                XCTAssertLessThan(FLog2.encode(lo), FLog2.encode(hi), "lo=\(lo) hi=\(hi)")
            } else {
                XCTAssertLessThanOrEqual(FLog2.encode(lo), FLog2.encode(hi) + seamStep, "lo=\(lo) hi=\(hi)")
            }
        }
    }

    /// INV-FLOG2-3: the pieces meet with only the datasheet's rounding step (`seamStep`, linear
    /// side higher), and cut2 is where cut1 lands on the log side. Codes from cut2 up to cut2 +
    /// seamStep come from both pieces; decode takes them as log, so x just below cut1 comes back
    /// through the other piece, about 4e-9 off, inside the round trip's 1e-8 tolerance.
    func testFLog2PiecesJoin() {
        XCTAssertGreaterThan(seamStep, 0)
        XCTAssertLessThan(seamStep, 1e-7)
        XCTAssertEqual(FLog2.encode(FLog2.cut1), FLog2.cut2, accuracy: 1e-9)
    }

    // MARK: - ExposureCompensation

    /// INV-EV-1: any number of dial turns stays within ±3 EV and within the device's range.
    /// INV-EV-2: the result is on the 1/3-stop grid, unless it is pinned to a device limit
    /// that is itself off the grid.
    func testSteppingStaysInRangeAndOnTheGrid() {
        var rng = SplitMix64(seed: 3)
        for seed in 0..<cases {
            // Devices go below and above zero; their limits need not be on the 1/3 grid.
            let device = Float.random(in: -8...(-0.5), using: &rng)...Float.random(in: 0.5...8, using: &rng)
            let lower = max(-ExposureCompensation.limitEV, device.lowerBound)
            let upper = min(ExposureCompensation.limitEV, device.upperBound)
            var ev: Float = 0
            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                ev = ExposureCompensation.stepped(ev, by: Int.random(in: -5...5, using: &rng), deviceRange: device)
                XCTAssertGreaterThanOrEqual(ev, lower, "case \(seed) device=\(device)")
                XCTAssertLessThanOrEqual(ev, upper, "case \(seed) device=\(device)")
                let onGrid = abs(ev * 3 - (ev * 3).rounded()) < 1e-4
                XCTAssertTrue(onGrid || ev == lower || ev == upper, "case \(seed) ev=\(ev) device=\(device)")
            }
        }
    }

    // MARK: - Recipe

    /// INV-RECIPE-1: any recipe reads back unchanged after it is saved.
    func testAnyRecipeSurvivesSaving() {
        var rng = SplitMix64(seed: 4)
        let names: [String?] = [nil, "", "My LUT", "夕方 の 色", "🎞️ film", #"quote " and \ slash"#]
        for seed in 0..<cases {
            var r = Recipe()
            r.filmSimulation = FilmSimulation.allCases.randomElement(using: &rng)!
            r.importedLUT = names.randomElement(using: &rng)!
            r.exposureEV = Double.random(in: -3...3, using: &rng)
            r.wbShiftR = Double.random(in: -9...9, using: &rng)
            r.wbShiftB = Double.random(in: -9...9, using: &rng)
            r.highlight = Double.random(in: -2...4, using: &rng)
            r.shadow = Double.random(in: -2...4, using: &rng)
            r.grainStrength = GrainStrength.allCases.randomElement(using: &rng)!
            r.grainSize = GrainSize.allCases.randomElement(using: &rng)!
            XCTAssertEqual(Recipe.decoded(from: r.encoded), r, "case \(seed): \(r)")
        }
    }
}

/// Small seeded generator (SplitMix64) so a failing case can be replayed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

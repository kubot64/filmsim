import XCTest

@testable import FilmSimCore

/// Property tests: rules that must hold for every input. Most throw thousands of random inputs
/// at the rule instead of a few hand-picked ones; their seeds are fixed in the source, so a
/// failure reproduces exactly, and its message names the failing input. The F-Log2 seam test
/// has no random inputs: it checks the datasheet constants where the two pieces meet.
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

    private static let lutNames: [String?] = [nil, "", "My LUT", "夕方 の 色", "🎞️ film", #"quote " and \ slash"#]

    /// Any recipe the develop screen can make, and values between its steps.
    private func randomRecipe(_ rng: inout SplitMix64) -> Recipe {
        var r = Recipe()
        r.filmSimulation = FilmSimulation.allCases.randomElement(using: &rng)!
        r.importedLUT = Self.lutNames.randomElement(using: &rng)!
        r.exposureEV = Double.random(in: -3...3, using: &rng)
        r.wbShiftR = Double.random(in: -9...9, using: &rng)
        r.wbShiftB = Double.random(in: -9...9, using: &rng)
        r.highlight = Double.random(in: -2...4, using: &rng)
        r.shadow = Double.random(in: -2...4, using: &rng)
        r.grainStrength = GrainStrength.allCases.randomElement(using: &rng)!
        r.grainSize = GrainSize.allCases.randomElement(using: &rng)!
        return r
    }

    /// INV-RECIPE-1: any recipe reads back unchanged after it is saved.
    func testAnyRecipeSurvivesSaving() {
        var rng = SplitMix64(seed: 4)
        for seed in 0..<cases {
            let r = randomRecipe(&rng)
            XCTAssertEqual(Recipe.decoded(from: r.encoded), r, "case \(seed): \(r)")
        }
    }

    // MARK: - RecipeBook

    /// INV-BOOK-1: whatever the user did to the saved recipes (import, rename and delete LUTs,
    /// change and select recipes, in any order), the book reads back with the same recipes, names,
    /// order and selection.
    func testAnyRecipeBookSurvivesSaving() {
        var rng = SplitMix64(seed: 5)
        let luts = ["Kodak", "FLog2_to_ETERNA", "夕方 の 色", #"quote " and \ slash"#]
        for seed in 0..<cases {
            var book = RecipeBook.initial(migrating: Bool.random(using: &rng) ? randomRecipe(&rng) : nil)
            var steps: [String] = []
            for _ in 0..<Int.random(in: 0...12, using: &rng) {
                let lut = luts.randomElement(using: &rng)!
                switch Int.random(in: 0..<5, using: &rng) {
                case 0:
                    book.addImportedLUT(named: lut, displayName: "\(lut) \(seed)")
                    steps.append("add \(lut)")
                case 1:
                    book.renameImportedLUT(named: lut, from: "\(lut) \(seed)", to: "renamed \(lut)")
                    steps.append("rename \(lut)")
                case 2:
                    book.removeImportedLUT(named: lut)
                    steps.append("remove \(lut)")
                case 3:
                    book.updateSelected(randomRecipe(&rng))
                    steps.append("update")
                default:
                    book.select(book.recipes.randomElement(using: &rng)!.id)
                    steps.append("select")
                }
            }
            let back = RecipeBook.decoded(from: book.encoded)
            XCTAssertEqual(back, book, "case \(seed): \(steps)")
            XCTAssertEqual(back.recipes.map(\.name), book.recipes.map(\.name), "case \(seed): \(steps)")
            XCTAssertEqual(back.selected.id, book.selected.id, "case \(seed): \(steps)")
        }
    }

    // MARK: - Grain

    /// INV-GRAIN-1: the grain weight is never negative, never above its peak 4/(3√3) at L = 1/3,
    /// and fades to 0 at black and white, so grain never shows in clipped shadows or highlights.
    func testGrainWeightStaysBetweenZeroAndItsPeak() {
        var rng = SplitMix64(seed: 6)
        let peak = 4 / (3 * 3.0.squareRoot())
        // Past 0 and 1 too: luma from a LUT can overshoot, and the weight must clamp it.
        for l in [-1, 0, 1, 2] + (0..<cases).map({ _ in Double.random(in: -0.5...1.5, using: &rng) }) {
            let w = Grain.weight(luminance: l)
            XCTAssertGreaterThanOrEqual(w, 0, "L=\(l)")
            XCTAssertLessThanOrEqual(w, peak + 1e-15, "L=\(l)")  // one ulp of the peak
            if l <= 0 || l >= 1 { XCTAssertEqual(w, 0, "L=\(l)") }
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

extension SplitMix64 {
    /// Three independent values in `range`: an RGB triple or a point in a LUT's cube.
    mutating func triple(in range: ClosedRange<Double> = 0...1) -> SIMD3<Double> {
        SIMD3(
            Double.random(in: range, using: &self), Double.random(in: range, using: &self),
            Double.random(in: range, using: &self))
    }
}

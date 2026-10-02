import XCTest
import simd

@testable import FilmSimCore

/// Property tests for the colour transforms after the LUT and for the gamut matrices. Same
/// shape as InvariantTests: fixed seeds, thousands of random inputs, the input in the message.
final class ColorInvariantTests: XCTestCase {
    private let cases = 5_000

    private func luma(_ c: SIMD3<Double>) -> Double { (c * BT709.luma).sum() }

    // MARK: - ToneCurve

    /// Highlight / shadow: off, a step the develop screen offers (-2...+4), or anywhere between.
    private func toneParameter(_ rng: inout SplitMix64) -> Double {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: return 0
        case 1: return Double(Int.random(in: -2...4, using: &rng))
        default: return Double.random(in: -2...4, using: &rng)
        }
    }

    /// INV-TONE-1: for every highlight / shadow, brighter in is never darker out. Pairs are close
    /// together (1e-6 to 0.1 apart) so a local dip cannot hide between them.
    func testToneCurveIsIncreasingForEveryRecipe() {
        var rng = SplitMix64(seed: 11)
        for _ in 0..<cases {
            let h = toneParameter(&rng), s = toneParameter(&rng)
            let lo = Double.random(in: 0...1, using: &rng)
            let hi = min(1, lo + pow(10, Double.random(in: -6 ... -1, using: &rng)))
            XCTAssertLessThanOrEqual(
                ToneCurve.evaluate(lo, highlight: h, shadow: s), ToneCurve.evaluate(hi, highlight: h, shadow: s),
                "lo=\(lo) hi=\(hi) highlight=\(h) shadow=\(s)")
        }
    }

    /// INV-TONE-2: highlight 0 and shadow 0 change nothing.
    func testToneCurveAtZeroIsIdentity() {
        var rng = SplitMix64(seed: 12)
        for _ in 0..<cases {
            let x = Double.random(in: 0...1, using: &rng)
            XCTAssertEqual(ToneCurve.evaluate(x, highlight: 0, shadow: 0), x, "x=\(x)")
        }
    }

    /// INV-TONE-3: black, the midpoint and white stay put for every highlight / shadow, so the
    /// controls bend the curve without moving its ends.
    func testToneCurveKeepsBlackMidAndWhite() {
        var rng = SplitMix64(seed: 13)
        for _ in 0..<cases {
            let h = toneParameter(&rng), s = toneParameter(&rng)
            for x in [0.0, 0.5, 1.0] {
                XCTAssertEqual(
                    ToneCurve.evaluate(x, highlight: h, shadow: s), x, accuracy: 1e-12,
                    "x=\(x) highlight=\(h) shadow=\(s)")
            }
        }
    }

    // MARK: - HighlightShoulder

    /// INV-SHOULDER-1: the same colour made brighter comes out no darker, channel by channel.
    func testShoulderIsIncreasingInBrightness() {
        var rng = SplitMix64(seed: 14)
        for _ in 0..<cases {
            var colour = rng.triple()
            guard colour.max() > 1e-3 else { continue }
            colour /= colour.max()
            let a = Double.random(in: 0...1, using: &rng), b = Double.random(in: 0...1, using: &rng)
            let (lo, hi) = (min(a, b), max(a, b))
            let dim = HighlightShoulder.evaluate(colour * lo), bright = HighlightShoulder.evaluate(colour * hi)
            for c in 0..<3 {
                XCTAssertLessThanOrEqual(dim[c], bright[c] + 1e-12, "colour=\(colour) lo=\(lo) hi=\(hi)")
            }
        }
    }

    /// INV-SHOULDER-2: at or below the knee nothing changes.
    func testShoulderLeavesTheKneeAndBelowAlone() {
        var rng = SplitMix64(seed: 15)
        var checked = 0
        while checked < cases {
            let colour = rng.triple()
            guard luma(colour) <= HighlightShoulder.knee else { continue }
            XCTAssertEqual(HighlightShoulder.evaluate(colour), colour, "rgb=\(colour)")
            checked += 1
        }
    }

    /// INV-SHOULDER-3: every channel is scaled by the same amount, so hue and saturation stay put,
    /// except where a channel clips at 1.
    func testShoulderKeepsTheRatiosOfUnclippedChannels() {
        var rng = SplitMix64(seed: 16)
        for _ in 0..<cases {
            let colour = rng.triple(in: 0.05...1)
            let out = HighlightShoulder.evaluate(colour)
            let free = (0..<3).filter { out[$0] < 1 }
            for i in free {
                for j in free where i < j {
                    XCTAssertEqual(out[i] * colour[j], out[j] * colour[i], accuracy: 1e-12, "rgb=\(colour) out=\(out)")
                }
            }
        }
    }

    // MARK: - WarmHue

    /// The colour with BT.709 Y' `y`, chroma length `chroma` and Cb/Cr angle `degrees`, or nil
    /// when it falls outside [0, 1].
    private func colour(y: Double, chroma: Double, degrees: Double) -> SIMD3<Double>? {
        let t = degrees * .pi / 180
        let cb = chroma * cos(t), cr = chroma * sin(t)
        let (kr, kg, kb) = (BT709.luma.x, BT709.luma.y, BT709.luma.z)
        let r = y + 2 * (1 - kr) * cr, b = y + 2 * (1 - kb) * cb
        let g = (y - kr * r - kb * b) / kg
        let c = SIMD3(r, g, b)
        return c.min() >= 0 && c.max() <= 1 ? c : nil
    }

    private func randomColour(_ rng: inout SplitMix64, degrees: Double) -> SIMD3<Double>? {
        colour(
            y: Double.random(in: 0.05...0.95, using: &rng), chroma: Double.random(in: 0.01...0.3, using: &rng),
            degrees: degrees)
    }

    /// INV-HUE-1: hues outside the window (center ± width) are left exactly as they are.
    func testWarmHueLeavesHuesOutsideTheWindowAlone() {
        var rng = SplitMix64(seed: 17)
        for _ in 0..<cases {
            // Anywhere from the window's far edge, the long way round, back to its near edge.
            let off = Double.random(in: WarmHue.width...(360 - WarmHue.width), using: &rng)
            guard let c = randomColour(&rng, degrees: WarmHue.center + off) else { continue }
            XCTAssertEqual(WarmHue.evaluate(c), c, "rgb=\(c) hue=\(WarmHue.center + off)")
        }
    }

    /// INV-HUE-2: no step at the window edges. Two colours 2e-3° apart on either side of an edge
    /// come out no further apart than they went in (the rotation fades to 0 there).
    func testWarmHueIsContinuousAtTheWindowEdges() {
        var rng = SplitMix64(seed: 18)
        for _ in 0..<cases {
            let edge = WarmHue.center + (Bool.random(using: &rng) ? WarmHue.width : -WarmHue.width)
            let y = Double.random(in: 0.05...0.95, using: &rng), chroma = Double.random(in: 0.01...0.3, using: &rng)
            guard let inside = colour(y: y, chroma: chroma, degrees: edge - 1e-3),
                let outside = colour(y: y, chroma: chroma, degrees: edge + 1e-3)
            else { continue }
            let jump = simd_reduce_max(abs(WarmHue.evaluate(inside) - WarmHue.evaluate(outside)))
            let gap = simd_reduce_max(abs(inside - outside))
            // 1 % slack: at 1e-3° from the edge the rotation is ~1e-9°, far inside it.
            XCTAssertLessThanOrEqual(jump, gap * 1.01 + 1e-12, "edge=\(edge) y=\(y) chroma=\(chroma)")
        }
    }

    /// INV-HUE-3: only the hue turns; Y' stays put unless a channel clips.
    func testWarmHueKeepsLuma() {
        var rng = SplitMix64(seed: 19)
        for _ in 0..<cases {
            let c = rng.triple()
            let out = WarmHue.evaluate(c)
            guard out.min() > 0, out.max() < 1 else { continue }
            XCTAssertEqual(luma(out), luma(c), accuracy: 1e-12, "rgb=\(c)")
        }
    }

    // MARK: - Gamut

    private let spaces: [RGBSpace] = [.fGamut, .displayP3, .bt709, .sGamut3, .sGamut3Cine]

    /// INV-GAMUT-1: to F-Gamut and back gives the colour back, for every space the pipeline reads.
    func testGamutRoundTripsThroughFGamut() {
        var rng = SplitMix64(seed: 20)
        for _ in 0..<cases {
            let space = spaces.randomElement(using: &rng)!
            let c = rng.triple()
            let back =
                RGBSpace.conversion(from: .fGamut, to: space) * (RGBSpace.conversion(from: space, to: .fGamut) * c)
            for ch in 0..<3 { XCTAssertEqual(back[ch], c[ch], accuracy: 1e-12, "\(space.name) rgb=\(c)") }
        }
    }

    /// INV-GAMUT-2: every space shares D65, so a grey stays the same grey between any two.
    func testGamutKeepsGreys() {
        var rng = SplitMix64(seed: 21)
        for _ in 0..<cases {
            let src = spaces.randomElement(using: &rng)!, dst = spaces.randomElement(using: &rng)!
            let v = Double.random(in: 0...16, using: &rng)
            let out = RGBSpace.conversion(from: src, to: dst) * SIMD3(repeating: v)
            // Matrix entries are O(1) and rounded to ~1e-16, so the error grows with v.
            for ch in 0..<3 {
                XCTAssertEqual(out[ch], v, accuracy: 1e-12 * max(1, v), "\(src.name)→\(dst.name) v=\(v)")
            }
        }
    }
}

import CoreImage
import XCTest

@testable import FilmSimCore

/// Runs the app's Metal kernels (ios/FilmSim/Shaders/FilmSim.metal) on the GPU over the research
/// pipeline's fixture inputs (TransformFixtures), so the production render path is held to the
/// Python and not only the Swift CPU functions.
///
/// The kernels live in the app target because Core Image kernels need `-fcikernel`, which
/// SwiftPM cannot pass. The test compiles the .metal file for macOS with `xcrun metal` once
/// per run.
final class MetalKernelTests: XCTestCase {
    private static var library: Data?
    private static var loadError: String?
    private let context = CIContext(options: [
        .workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .workingFormat: CIFormat.RGBAf
    ])

    override class func setUp() {
        super.setUp()
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FilmSimCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FilmSimCore
            .deletingLastPathComponent()  // ios
            .appendingPathComponent("FilmSim/Shaders/FilmSim.metal")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FilmSimMetalKernelTests-\(UUID())")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let air = dir.appendingPathComponent("FilmSim.air").path
            let lib = dir.appendingPathComponent("FilmSim.metallib").path
            try xcrun(["-sdk", "macosx", "metal", "-fcikernel", "-c", source.path, "-o", air])
            try xcrun(["-sdk", "macosx", "metallib", "-cikernel", air, "-o", lib])
            library = try Data(contentsOf: URL(fileURLWithPath: lib))
        } catch {
            loadError = "\(error)"
        }
    }

    private static func xcrun(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "xcrun", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func kernel(_ name: String) throws -> CIColorKernel {
        guard let data = Self.library else {
            XCTFail("could not compile FilmSim.metal: \(Self.loadError ?? "unknown")")
            throw XCTSkip("no Metal library")
        }
        return try CIColorKernel(functionName: name, fromMetalLibraryData: data)
    }

    /// A 1-pixel-high image, one RGB triple per pixel, with no colour management.
    private func image(_ pixels: [SIMD3<Float>]) -> CIImage {
        var rgba: [Float] = []
        for p in pixels { rgba += [p.x, p.y, p.z, 1] }
        let data = rgba.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data, bytesPerRow: pixels.count * 16,
            size: CGSize(width: pixels.count, height: 1), format: .RGBAf, colorSpace: nil
        )
    }

    private func render(_ image: CIImage) -> [SIMD3<Float>] {
        let n = Int(image.extent.width)
        var out = [Float](repeating: 0, count: n * 4)
        context.render(image, toBitmap: &out, rowBytes: n * 16, bounds: image.extent, format: .RGBAf, colorSpace: nil)
        return (0..<n).map { SIMD3(out[$0 * 4], out[$0 * 4 + 1], out[$0 * 4 + 2]) }
    }

    private func grey(_ values: [Double]) -> CIImage {
        image(values.map { SIMD3(repeating: Float($0)) })
    }

    // MARK: - Against the research pipeline (TransformFixtures)

    /// Float32 on the GPU: inputs round to 24-bit mantissas and the kernels chain a few fast-math
    /// ops (log2, pow, atan2, cos) on values up to 1, each a few ulps, so about 1e-6 per channel.
    private let gpuAccuracy = 2e-6

    private func assertMatches(
        _ got: [SIMD3<Float>], _ cases: [TransformFixtures.Case], _ expected: (TransformFixtures.Case) -> SIMD3<Double>,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(got.count, cases.count, file: file, line: line)
        for (c, g) in zip(cases, got) {
            let e = expected(c)
            for ch in 0..<3 {
                XCTAssertEqual(
                    Double(g[ch]), e[ch], accuracy: gpuAccuracy, "channel \(ch) \(c)", file: file, line: line)
            }
        }
    }

    func testFLog2EncodeMatchesPython() throws {
        let cases = TransformFixtures.cases("flog2_encode")
        let k = try kernel("flog2Encode")
        let input = grey(cases.map { $0.in[0] })
        assertMatches(render(k.apply(extent: input.extent, arguments: [input])!), cases) { SIMD3(repeating: $0.out[0]) }
    }

    func testShoulderMatchesPython() throws {
        let cases = TransformFixtures.cases("highlight_shoulder")
        let k = try kernel("xSeriesShoulder")
        let input = image(cases.map { SIMD3<Float>($0.rgbIn) })
        let args: [Any] = [
            input,
            NSNumber(value: Float(HighlightShoulder.knee)),
            NSNumber(value: Float(HighlightShoulder.gamma))
        ]
        assertMatches(render(k.apply(extent: input.extent, arguments: args)!), cases) { $0.rgbOut }
    }

    func testWarmHueMatchesPython() throws {
        let cases = TransformFixtures.cases("warm_hue")
        let k = try kernel("xSeriesWarmHue")
        let input = image(cases.map { SIMD3<Float>($0.rgbIn) })
        let args: [Any] = [
            input,
            NSNumber(value: Float(WarmHue.degrees)),
            NSNumber(value: Float(WarmHue.center)),
            NSNumber(value: Float(WarmHue.width))
        ]
        assertMatches(render(k.apply(extent: input.extent, arguments: args)!), cases) { $0.rgbOut }
    }

    /// The kernel takes one highlight / shadow per call, so the cases render in groups that share them.
    func testToneCurveMatchesPython() throws {
        let k = try kernel("toneCurve")
        let groups = Dictionary(grouping: TransformFixtures.cases("tone_curve")) { $0.params ?? [] }
        for cases in groups.values {
            let tone = cases[0].tone
            let input = grey(cases.map { $0.in[0] })
            let args: [Any] = [input, NSNumber(value: Float(tone.highlight)), NSNumber(value: Float(tone.shadow))]
            assertMatches(render(k.apply(extent: input.extent, arguments: args)!), cases) {
                SIMD3(repeating: $0.out[0])
            }
        }
    }

    /// out = c + noise * weight(L) * amp, L the BT.709 luma of c. Each case's pixel is a colour
    /// whose luma is the fixture's L (grey plus a zero-luma tint), so the kernel's own luma is
    /// checked too; a constant noise isolates weight × amplitude. Both signs, both amplitudes.
    func testGrainApplyUsesPythonWeight() throws {
        let cases = TransformFixtures.cases("grain_weight")
        let k = try kernel("grainApply")
        // Zero luma (kr(kg + kb) − kg·kr − kb·kr = 0) and every channel moved, so a kernel that
        // read one channel instead of the luma would be off.
        let (kr, kg, kb) = (BT709.luma.x, BT709.luma.y, BT709.luma.z)
        let tint = SIMD3(kg + kb, -kr, -kr)
        let colours = cases.map { c -> SIMD3<Double> in
            let l = c.in[0]
            return SIMD3(repeating: l) + tint * min((1 - l) / (kg + kb), l / kr)
        }
        let input = image(colours.map { SIMD3<Float>($0) })
        for (noise, amp) in [(1.0, GrainStrength.strong.amplitude), (-0.7, GrainStrength.weak.amplitude)] {
            let noiseImage = image(Array(repeating: SIMD3(Float(noise), 0, 0), count: cases.count))
            let args: [Any] = [input, noiseImage, NSNumber(value: Float(amp))]
            let out = render(k.apply(extent: input.extent, arguments: args)!)
            for ((c, colour), got) in zip(zip(cases, colours), out) {
                let expected = (colour + SIMD3(repeating: noise * c.out[0] * amp)).clamped(
                    lowerBound: .zero, upperBound: SIMD3(repeating: 1))
                for ch in 0..<3 {
                    XCTAssertEqual(
                        Double(got[ch]), expected[ch], accuracy: gpuAccuracy,
                        "channel \(ch) rgb=\(colour) noise=\(noise) amp=\(amp) \(c)")
                }
            }
        }
    }

    // MARK: - Properties

    /// INV-GRAIN-2: grain off leaves every pixel as it was, at any grain size and preview scale.
    /// Renders an image per case, so fewer cases than the pure-maths property tests.
    func testGrainOffChangesNothing() throws {
        let k = try kernel("grainApply")
        var rng = SplitMix64(seed: 41)
        for seed in 0..<200 {
            let pixels = (0..<Int.random(in: 1...64, using: &rng)).map { _ in
                SIMD3<Float>(
                    Float.random(in: 0...1, using: &rng), Float.random(in: 0...1, using: &rng),
                    Float.random(in: 0...1, using: &rng))
            }
            let size = GrainSize.allCases.randomElement(using: &rng)!
            let scale = Double.random(in: 0.1...1, using: &rng)
            let input = image(pixels)
            let out = Grain.apply(to: input, strength: .off, size: size, pixelScale: scale, kernel: k)
            XCTAssertEqual(out.extent, input.extent, "case \(seed)")
            XCTAssertEqual(render(out), pixels, "case \(seed) size=\(size) scale=\(scale)")
        }
    }
}

import CoreImage
import XCTest
@testable import FilmSimCore

/// Runs the app's Metal kernels (ios/FilmSim/Shaders/FilmSim.metal) on the GPU and compares
/// them with the Python golden values, so the production render path is covered and not
/// only the Swift CPU functions.
///
/// The kernels live in the app target because Core Image kernels need `-fcikernel`, which
/// SwiftPM cannot pass. The test compiles the .metal file for macOS with `xcrun metal` once
/// per run. Float32 on the GPU, so tolerances are around 1e-6 rather than 1e-12.
final class MetalKernelTests: XCTestCase {
    private static var library: Data?
    private static var loadError: String?
    private let context = CIContext(options: [
        .workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .workingFormat: CIFormat.RGBAf,
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

    func testFLog2EncodeMatchesPython() throws {
        // research: FLOG2.encode (filmsim/flog2.py).
        let cases: [(Double, Double)] = [
            (0.0, 0.092864000000), (0.0005, 0.097263730500), (0.000889, 0.100686685371),
            (0.01, 0.158797483886), (0.18, 0.391007241891), (0.5, 0.495604115612),
            (0.9, 0.557132363979), (1.0, 0.568219370444), (4.0, 0.714967701026), (16.0, 0.862408929224),
        ]
        let k = try kernel("flog2Encode")
        let input = grey(cases.map(\.0))
        let out = render(k.apply(extent: input.extent, arguments: [input])!)
        for ((x, expected), got) in zip(cases, out) {
            for c in 0..<3 { XCTAssertEqual(Double(got[c]), expected, accuracy: 2e-6, "x = \(x)") }
        }
    }

    func testToneCurveMatchesPython() throws {
        // research/tests/test_tone.py test_golden_points.
        let cases: [(x: Double, highlight: Double, shadow: Double, expected: Double)] = [
            (0.75, 4, 0, 0.805528455647), (0.25, 0, 4, 0.189257114166), (0.75, -2, 0, 0.724982211387),
            (0.25, 0, -2, 0.299342958294), (0.8, 2, 3, 0.828519484754),
        ]
        let k = try kernel("toneCurve")
        for c in cases {
            let input = grey([c.x])
            let args: [Any] = [input, NSNumber(value: Float(c.highlight)), NSNumber(value: Float(c.shadow))]
            let got = render(k.apply(extent: input.extent, arguments: args)!)[0]
            for ch in 0..<3 { XCTAssertEqual(Double(got[ch]), c.expected, accuracy: 2e-6, "\(c)") }
        }
    }

    func testToneCurveMatchesSwiftAcrossARamp() throws {
        let k = try kernel("toneCurve")
        let xs = stride(from: 0.0, through: 1.0, by: 1.0 / 64).map { $0 }
        let input = grey(xs)
        for (h, s) in [(4.0, 0.0), (0.0, 4.0), (-2.0, -2.0), (2.0, 3.0)] {
            let args: [Any] = [input, NSNumber(value: Float(h)), NSNumber(value: Float(s))]
            let out = render(k.apply(extent: input.extent, arguments: args)!)
            for (x, got) in zip(xs, out) {
                XCTAssertEqual(Double(got.x), ToneCurve.evaluate(x, highlight: h, shadow: s), accuracy: 2e-6, "x=\(x) h=\(h) s=\(s)")
            }
        }
    }

    func testShoulderMatchesPython() throws {
        // research/tests/test_tone.py test_shoulder_golden_points, plus the fixed points.
        let cases: [(Double, Double)] = [
            (0.0, 0.0), (0.45, 0.45), (0.6, 0.6), (0.7, 0.721353129146), (0.8, 0.8472135955),
            (0.9, 0.94107653273), (0.95, 0.973618990031), (1.0, 1.0),
        ]
        let k = try kernel("xSeriesShoulder")
        let input = grey(cases.map(\.0))
        let out = render(k.apply(extent: input.extent, arguments: [input])!)
        for ((x, expected), got) in zip(cases, out) {
            for c in 0..<3 { XCTAssertEqual(Double(got[c]), expected, accuracy: 2e-6, "x = \(x)") }
        }
    }

    func testShoulderMatchesSwiftOnColours() throws {
        let colours: [SIMD3<Double>] = [[0.9, 0.6, 0.5], [0.95, 0.9, 0.2], [0.3, 0.8, 1.0], [0.7, 0.7, 0.72]]
        let k = try kernel("xSeriesShoulder")
        let input = image(colours.map { SIMD3<Float>($0) })
        let out = render(k.apply(extent: input.extent, arguments: [input])!)
        for (rgb, got) in zip(colours, out) {
            let expected = HighlightShoulder.evaluate(rgb)
            for c in 0..<3 { XCTAssertEqual(Double(got[c]), expected[c], accuracy: 2e-6, "\(rgb)") }
        }
    }

    func testGrainApplyUsesPythonWeightAndAmplitude() throws {
        // research/filmsim/grain.py: out = c + noise * sqrt(L)(1-L)*2 * amp, L = BT.709 luma.
        // A constant noise image isolates the weight.
        let k = try kernel("grainApply")
        let colours: [SIMD3<Double>] = [[0, 0, 0], [0.25, 0.25, 0.25], [0.5, 0.5, 0.5], [0.8, 0.6, 0.4], [1, 1, 1]]
        let input = image(colours.map { SIMD3<Float>($0) })
        for (noise, amp) in [(1.0, Grain.amplitude(.strong)), (-0.7, Grain.amplitude(.weak))] {
            let noiseImage = image(Array(repeating: SIMD3(Float(noise), 0, 0), count: colours.count))
            let args: [Any] = [input, noiseImage, NSNumber(value: Float(amp))]
            let out = render(k.apply(extent: input.extent, arguments: args)!)
            for (rgb, got) in zip(colours, out) {
                let l = (rgb * HighlightShoulder.luma).sum()
                let delta = noise * Grain.weight(luminance: l) * amp
                for c in 0..<3 {
                    let expected = min(max(rgb[c] + delta, 0), 1)
                    XCTAssertEqual(Double(got[c]), expected, accuracy: 2e-6, "\(rgb) noise \(noise)")
                }
            }
        }
    }
}

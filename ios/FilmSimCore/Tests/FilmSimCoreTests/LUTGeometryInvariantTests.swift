import CoreGraphics
import CoreImage
import XCTest
import simd

@testable import FilmSimCore

/// Property tests for the 3D LUT lookup and the framing geometry. Same shape as InvariantTests:
/// fixed seeds, random inputs, the input in the message.
final class LUTGeometryInvariantTests: XCTestCase {
    private let cases = 5_000

    // MARK: - CubeLUT

    /// A LUT whose node (r, g, b) holds `value(r, g, b)`, red fastest as CIColorCube lays it out.
    private func lut(size n: Int, _ value: (Int, Int, Int) -> SIMD3<Float>) -> CubeLUT {
        var floats: [Float] = []
        floats.reserveCapacity(n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let v = value(r, g, b)
                    floats += [v.x, v.y, v.z, 1]
                }
            }
        }
        return CubeLUT(title: "test", size: n, floats: floats)
    }

    private func identity(size n: Int) -> CubeLUT {
        lut(size: n) { r, g, b in SIMD3(Float(r), Float(g), Float(b)) / Float(n - 1) }
    }

    /// INV-LUT-1: the identity LUT returns every input, clamped to [0, 1], at any grid size.
    /// Nodes are Float, so each is up to 6e-8 off; trilinear weights do not add to that.
    func testIdentityLUTReturnsItsInput() {
        var rng = SplitMix64(seed: 31)
        let luts = Dictionary(uniqueKeysWithValues: [2, 3, 5, 17, 33].map { ($0, identity(size: $0)) })
        for _ in 0..<cases {
            let n = luts.keys.randomElement(using: &rng)!
            let p = rng.triple(in: -0.2...1.2)
            let expected = simd_clamp(p, SIMD3(repeating: 0), SIMD3(repeating: 1))
            let got = luts[n]!.sample(p)
            for c in 0..<3 { XCTAssertEqual(got[c], expected[c], accuracy: 1e-7, "size=\(n) p=\(p)") }
        }
    }

    /// INV-LUT-2: an interpolated value lies within the eight nodes around it, channel by channel,
    /// so the lookup never invents a colour the LUT does not hold nearby.
    func testInterpolationStaysWithinTheSurroundingNodes() {
        var rng = SplitMix64(seed: 32)
        let tables = (0..<20).map { _ -> CubeLUT in
            let n = Int.random(in: 2...9, using: &rng)
            var values: [SIMD3<Float>] = []
            for _ in 0..<(n * n * n) { values.append(SIMD3<Float>(rng.triple(in: -0.5...1.5))) }
            return lut(size: n) { r, g, b in values[(b * n + g) * n + r] }
        }
        for _ in 0..<cases {
            let table = tables.randomElement(using: &rng)!
            let n = table.size
            let p = rng.triple()
            // The cell holding p; the top face belongs to the last cell.
            let i = (0..<3).map { min(Int((p[$0] * Double(n - 1)).rounded(.down)), n - 2) }
            var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
            for dr in 0...1 {
                for dg in 0...1 {
                    for db in 0...1 {
                        let v = table.node(r: i[0] + dr, g: i[1] + dg, b: i[2] + db)
                        let node = SIMD3(Double(v.0), Double(v.1), Double(v.2))
                        lo = simd_min(lo, node)
                        hi = simd_max(hi, node)
                    }
                }
            }
            let got = table.sample(p)
            for c in 0..<3 {
                // Weights sum to 1 in double; 1e-9 covers their rounding on nodes up to 1.5.
                XCTAssertGreaterThanOrEqual(got[c], lo[c] - 1e-9, "size=\(n) p=\(p)")
                XCTAssertLessThanOrEqual(got[c], hi[c] + 1e-9, "size=\(n) p=\(p)")
            }
        }
    }

    /// INV-LUT-3: a LUT written as .cube text reads back the same, to the six decimals written.
    func testCubeTextReadsBack() throws {
        var rng = SplitMix64(seed: 33)
        for seed in 0..<200 {
            let n = Int.random(in: 2...9, using: &rng)
            var values: [SIMD3<Float>] = []
            // Wider than colours: LUTs overshoot, and the text must carry the sign and the integer part.
            for _ in 0..<(n * n * n) { values.append(SIMD3<Float>(rng.triple(in: -2...4))) }
            let table = lut(size: n) { r, g, b in values[(b * n + g) * n + r] }
            let back = try CubeLUT(text: table.cubeText)
            XCTAssertEqual(back.size, n, "case \(seed)")
            for b in 0..<n {
                for g in 0..<n {
                    for r in 0..<n {
                        let (x, y) = (table.node(r: r, g: g, b: b), back.node(r: r, g: g, b: b))
                        XCTAssertEqual(x.0, y.0, accuracy: 6e-7, "case \(seed) node \(r),\(g),\(b)")
                        XCTAssertEqual(x.1, y.1, accuracy: 6e-7, "case \(seed) node \(r),\(g),\(b)")
                        XCTAssertEqual(x.2, y.2, accuracy: 6e-7, "case \(seed) node \(r),\(g),\(b)")
                    }
                }
            }
        }
    }

    // MARK: - SensorCrop

    /// INV-CROP-1: for any frame and focal length the crop is 3:2, centred, and inside the frame.
    func testCropIsThreeByTwoCentredAndInside() {
        var rng = SplitMix64(seed: 34)
        for _ in 0..<cases {
            let extent = CGRect(
                x: Double.random(in: -1000...1000, using: &rng), y: Double.random(in: -1000...1000, using: &rng),
                width: Double.random(in: 1...10_000, using: &rng), height: Double.random(in: 1...10_000, using: &rng))
            let focal = FocalLength.allCases.randomElement(using: &rng)!
            let r = SensorCrop.rectThreeByTwo(in: extent, focalLength: focal)
            let eps = 1e-9 * max(extent.width, extent.height, 1)
            let message = "extent=\(extent) \(focal.displayName)"
            XCTAssertEqual(r.width, r.height * 3 / 2, accuracy: eps, message)
            XCTAssertEqual(r.midX, extent.midX, accuracy: eps, message)
            XCTAssertEqual(r.midY, extent.midY, accuracy: eps, message)
            XCTAssertGreaterThanOrEqual(r.minX, extent.minX - eps, message)
            XCTAssertGreaterThanOrEqual(r.minY, extent.minY - eps, message)
            XCTAssertLessThanOrEqual(r.maxX, extent.maxX + eps, message)
            XCTAssertLessThanOrEqual(r.maxY, extent.maxY + eps, message)
        }
    }

    /// INV-CROP-2: 24mm keeps as much of the frame as a 3:2 can: it touches two opposite edges.
    func testWideCropFillsTheFrame() {
        var rng = SplitMix64(seed: 35)
        for _ in 0..<cases {
            let extent = CGRect(
                x: 0, y: 0, width: Double.random(in: 1...10_000, using: &rng),
                height: Double.random(in: 1...10_000, using: &rng))
            let r = SensorCrop.rectThreeByTwo(in: extent, focalLength: .mm24)
            let eps = 1e-9 * max(extent.width, extent.height)
            let touches = abs(r.width - extent.width) < eps || abs(r.height - extent.height) < eps
            XCTAssertTrue(touches, "extent=\(extent) crop=\(r)")
        }
    }

    // MARK: - PreviewGeometry

    private func sensorAspect(_ rng: inout SplitMix64) -> Double {
        [4.0 / 3.0, 16.0 / 9.0, 3.0 / 2.0, 1].randomElement(using: &rng)! * Double.random(in: 0.9...1.1, using: &rng)
    }

    /// INV-GEOM-1: every point of the preview maps to a device point inside the crop, which is
    /// inside the sensor, and the preview's corners land on the crop's corners turned clockwise.
    func testEveryPreviewPointLandsInsideTheCrop() {
        var rng = SplitMix64(seed: 36)
        for _ in 0..<cases {
            let aspect = sensorAspect(&rng)
            let focal = FocalLength.allCases.randomElement(using: &rng)!
            let crop = PreviewGeometry.crop(sensorAspect: aspect, focalLength: focal)
            let message = "aspect=\(aspect) \(focal.displayName)"
            XCTAssertTrue(
                CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-12, dy: -1e-12).contains(crop), message)
            let view = CGPoint(x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...1, using: &rng))
            let device = PreviewGeometry.devicePoint(fromView: view, crop: crop)
            XCTAssertTrue(crop.insetBy(dx: -1e-12, dy: -1e-12).contains(device), "\(message) view=\(view)")
            let topLeft = PreviewGeometry.devicePoint(fromView: .zero, crop: crop)
            XCTAssertEqual(topLeft.x, crop.minX, accuracy: 1e-12, message)
            XCTAssertEqual(topLeft.y, crop.maxY, accuracy: 1e-12, message)
        }
    }

    /// INV-GEOM-2: a tap anywhere, even off the preview, gives a focus point on the preview whose
    /// frame is wholly inside the view.
    func testAnyTapGivesAFrameInsideTheView() {
        var rng = SplitMix64(seed: 37)
        let frame = CGSize(width: 72, height: 72)
        for _ in 0..<cases {
            let bounds = CGRect(
                x: 0, y: 0, width: Double.random(in: 100...1500, using: &rng),
                height: Double.random(in: 100...1500, using: &rng))
            let tap = CGPoint(
                x: Double.random(in: -200...(bounds.width + 200), using: &rng),
                y: Double.random(in: -200...(bounds.height + 200), using: &rng))
            let message = "bounds=\(bounds.size) tap=\(tap)"
            guard let p = PreviewGeometry.focusViewPoint(forTap: tap, in: bounds, frameSize: frame) else {
                XCTFail("no focus point: \(message)")
                continue
            }
            let image = PreviewGeometry.imageRect(in: bounds)
            let centre = CGPoint(x: image.minX + p.x * image.width, y: image.minY + p.y * image.height)
            let drawn = CGRect(x: centre.x - 36, y: centre.y - 36, width: 72, height: 72)
            XCTAssertTrue(bounds.insetBy(dx: -1e-9, dy: -1e-9).contains(drawn), message)
            XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), message)
        }
    }

    /// INV-GEOM-3: preview point → device point → drawn preview comes back to the same preview
    /// point, at every focal length: a mark put on the sensor where a tap maps is drawn under the
    /// tap. Renders an image per case, so fewer cases than the pure-maths tests.
    func testTapMapsToWhereThePreviewDrawsIt() throws {
        var rng = SplitMix64(seed: 38)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let size = CGSize(width: 200, height: 300)
        for focal in FocalLength.allCases {
            for _ in 0..<20 {
                let sensor = CGSize(width: 800, height: (800 / sensorAspect(&rng)).rounded())
                let crop = PreviewGeometry.crop(sensorAspect: sensor.width / sensor.height, focalLength: focal)
                let view = CGPoint(
                    x: Double.random(in: 0.1...0.9, using: &rng), y: Double.random(in: 0.1...0.9, using: &rng))
                let device = PreviewGeometry.devicePoint(fromView: view, crop: crop)
                // CIImage is bottom-left origin; device points are top-left.
                let mark = CIImage(color: .white).cropped(
                    to: CGRect(
                        x: device.x * sensor.width - 4, y: (1 - device.y) * sensor.height - 4, width: 8, height: 8))
                let drawn = mark.composited(
                    over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: sensor))
                )
                .livePreviewFrame(focalLength: focal, filling: size)
                let message = "sensor=\(sensor) \(focal.displayName) view=\(view)"
                // The extent may round to the next whole pixel.
                XCTAssertEqual(drawn.extent.width, size.width, accuracy: 0.5, message)
                XCTAssertEqual(drawn.extent.height, size.height, accuracy: 0.5, message)
                let found = try XCTUnwrap(centroid(of: drawn, size: size, context: context), message)
                // The centroid of a mark a few pixels wide, snapped to a 200×300 grid: within 2–3 px.
                XCTAssertEqual(found.x / size.width, view.x, accuracy: 0.01, message)
                XCTAssertEqual(1 - found.y / size.height, view.y, accuracy: 0.01, message)
            }
        }
    }

    /// Centre of the bright pixels, in CIImage coordinates.
    private func centroid(of image: CIImage, size: CGSize, context: CIContext) -> CGPoint? {
        let w = Int(size.width), h = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        context.render(
            image, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8,
            colorSpace: nil)
        var sx = 0.0, sy = 0.0, n = 0.0
        for row in 0..<h {
            for col in 0..<w where pixels[(row * w + col) * 4] > 127 {
                // Bitmap rows run top to bottom; CIImage y runs bottom to top.
                sx += Double(col) + 0.5
                sy += Double(h - row) - 0.5
                n += 1
            }
        }
        return n > 0 ? CGPoint(x: sx / n, y: sy / n) : nil
    }
}

import CoreImage
import XCTest
import simd
@testable import FilmSimCore

final class ColorMatrixTests: XCTestCase {
    func testCIColorMatrixDotsTheInputWithEachVector() {
        // Measured layout: input (1,0,0) with these vectors yields (0.1, 0.4, 0.7).
        let vectors = ColorMatrixVectors(
            r: SIMD3(0.1, 0.2, 0.3),
            g: SIMD3(0.4, 0.5, 0.6),
            b: SIMD3(0.7, 0.8, 0.9)
        )
        let out = render(red: 1, green: 0, blue: 0, vectors: vectors)
        XCTAssertEqual(out.x, 0.1, accuracy: 1e-4)
        XCTAssertEqual(out.y, 0.4, accuracy: 1e-4)
        XCTAssertEqual(out.z, 0.7, accuracy: 1e-4)
    }

    func testP3ToFGamutPreservesWhiteAndMapsRedToFirstColumn() {
        let m = RGBSpace.conversion(from: .displayP3, to: .fGamut)
        let vectors = ColorMatrixVectors.contributions(m, gains: SIMD3(1, 1, 1))

        let white = render(red: 1, green: 1, blue: 1, vectors: vectors)
        XCTAssertEqual(white.x, 1, accuracy: 1e-4)
        XCTAssertEqual(white.y, 1, accuracy: 1e-4)
        XCTAssertEqual(white.z, 1, accuracy: 1e-4)

        let red = render(red: 1, green: 0, blue: 0, vectors: vectors)
        XCTAssertEqual(red.x, m[0, 0], accuracy: 1e-4)
        XCTAssertEqual(red.y, m[0, 1], accuracy: 1e-4)
        XCTAssertEqual(red.z, m[0, 2], accuracy: 1e-4)
    }

    func testInputGainScalesTheSourceChannel() {
        let m = RGBSpace.conversion(from: .displayP3, to: .fGamut)
        let vectors = ColorMatrixVectors.contributions(m, gains: SIMD3(2, 1, 1))
        let red = render(red: 1, green: 0, blue: 0, vectors: vectors)
        XCTAssertEqual(red.x, m[0, 0] * 2, accuracy: 1e-4)
        XCTAssertEqual(red.y, m[0, 1] * 2, accuracy: 1e-4)
        XCTAssertEqual(red.z, m[0, 2] * 2, accuracy: 1e-4)
    }

    private func render(red: Double, green: Double, blue: Double, vectors: ColorMatrixVectors) -> SIMD3<Double> {
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: space])
        guard let color = CIColor(
            red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1, colorSpace: space
        ) else {
            XCTFail("CIColor init failed")
            return .zero
        }
        let image = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let filtered = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": vectors.rVector,
            "inputGVector": vectors.gVector,
            "inputBVector": vectors.bVector,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            context.render(
                filtered,
                toBitmap: raw.baseAddress!,
                rowBytes: MemoryLayout<Float>.size * 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBAf,
                colorSpace: space
            )
        }
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }
}

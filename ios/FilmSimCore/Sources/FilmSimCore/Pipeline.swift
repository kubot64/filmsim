import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Core Image chain mirroring research/filmsim/pipeline.py.
///
/// linear P3 -> WB gains -> exposure -> P3→F-Gamut matrix -> F-Log2 (Metal kernel) -> official LUT -> tone -> grain
public struct Pipeline {
    public let flog2Kernel: CIColorKernel
    public let luts: [FilmSimulation: CubeLUT]

    public init(flog2Kernel: CIColorKernel, luts: [FilmSimulation: CubeLUT]) {
        self.flog2Kernel = flog2Kernel
        self.luts = luts
    }

    /// Loads the `flog2Encode` CIColorKernel from the app's default.metallib
    /// (the .metal file lives in the app target because CI kernels need `-fcikernel`).
    public static func loadFLog2Kernel(bundle: Bundle = .main) throws -> CIColorKernel {
        guard let url = bundle.url(forResource: "default", withExtension: "metallib") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try CIColorKernel(functionName: "flog2Encode", fromMetalLibraryData: try Data(contentsOf: url))
    }

    public func render(_ linear: CIImage, recipe: Recipe) -> CIImage? {
        guard let lut = luts[recipe.filmSimulation] else { return nil }

        // WB shift + exposure, in linear.
        let gains = recipe.wbGains * pow(2, recipe.exposureEV)
        let m = RGBSpace.conversion(from: .displayP3, to: .fGamut)
        let matrixed = linear.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: m[0, 0] * gains.x, y: m[1, 0] * gains.y, z: m[2, 0] * gains.z, w: 0),
            "inputGVector": CIVector(x: m[0, 1] * gains.x, y: m[1, 1] * gains.y, z: m[2, 1] * gains.z, w: 0),
            "inputBVector": CIVector(x: m[0, 2] * gains.x, y: m[1, 2] * gains.y, z: m[2, 2] * gains.z, w: 0),
        ])

        guard let logImage = flog2Kernel.apply(extent: matrixed.extent, arguments: [matrixed]) else { return nil }

        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = logImage
        cube.cubeDimension = Float(lut.size)
        cube.cubeData = lut.rgbaData
        cube.colorSpace = CGColorSpace(name: CGColorSpace.itur_709)
        guard var out = cube.outputImage else { return nil }

        out = ToneCurve.apply(to: out, highlight: recipe.highlight, shadow: recipe.shadow)
        out = Grain.apply(to: out, strength: recipe.grainStrength, size: recipe.grainSize)
        return out
    }
}

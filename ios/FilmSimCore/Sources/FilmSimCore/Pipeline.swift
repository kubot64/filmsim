import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Core Image chain mirroring research/filmsim/pipeline.py.
///
/// linear P3 → WB and exposure → P3→F-Gamut → F-Log2 → official LUT → tone → grain.
/// The LUT is indexed by the F-Log2 code values themselves (`CIColorCube`, no color-space
/// conversion). Its output is already BT.709 gamma; the caller tags the file, it does not
/// convert again.
public struct Pipeline {
    public struct Kernels {
        public let flog2: CIColorKernel
        public let tone: CIColorKernel
        public let grain: CIColorKernel

        /// Loads kernels from the app's default.metallib. The .metal file lives in the app
        /// target because CI kernels need `-fcikernel`.
        public static func load(bundle: Bundle = .main) throws -> Kernels {
            guard let url = bundle.url(forResource: "default", withExtension: "metallib") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try Data(contentsOf: url)
            return Kernels(
                flog2: try CIColorKernel(functionName: "flog2Encode", fromMetalLibraryData: data),
                tone: try CIColorKernel(functionName: "toneCurve", fromMetalLibraryData: data),
                grain: try CIColorKernel(functionName: "grainApply", fromMetalLibraryData: data)
            )
        }
    }

    public let kernels: Kernels
    public let luts: [FilmSimulation: CubeLUT]

    public init(kernels: Kernels, luts: [FilmSimulation: CubeLUT]) {
        self.kernels = kernels
        self.luts = luts
    }

    /// `grainPixelScale` multiplies the grain sigma. Pass the CIRAWFilter scale used for
    /// a preview so grain stays the same size relative to the frame.
    public func render(_ linear: CIImage, recipe: Recipe, grainPixelScale: Double = 1) -> CIImage? {
        guard let lut = luts[recipe.filmSimulation] else { return nil }

        let gains = recipe.wbGains * pow(2, recipe.exposureEV)
        let m = RGBSpace.conversion(from: .displayP3, to: .fGamut)
        let c = ColorMatrixVectors.contributions(m, gains: gains)
        let matrixed = linear.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": c.rVector,
            "inputGVector": c.gVector,
            "inputBVector": c.bVector,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        guard let logImage = kernels.flog2.apply(extent: matrixed.extent, arguments: [matrixed]) else {
            return nil
        }

        let cube = CIFilter.colorCube()
        cube.inputImage = logImage
        cube.cubeDimension = Float(lut.size)
        cube.cubeData = lut.rgbaData
        guard var out = cube.outputImage else { return nil }

        out = ToneCurve.apply(to: out, highlight: recipe.highlight, shadow: recipe.shadow, kernel: kernels.tone)
        out = Grain.apply(
            to: out,
            strength: recipe.grainStrength,
            size: recipe.grainSize,
            pixelScale: grainPixelScale,
            kernel: kernels.grain
        )
        return out
    }
}

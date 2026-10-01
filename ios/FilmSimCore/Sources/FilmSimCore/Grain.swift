import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Film grain: luminance-weighted monochrome noise, matching research/filmsim/grain.py.
///
/// The weight is exact. The noise field is uniform noise, blurred, then scaled so its
/// standard deviation matches scipy's `gaussian_filter` followed by `/= std`.
/// Core Image's gaussian is not bit-identical to scipy, so the GPU amplitude is approximate.
public enum Grain {
    /// `sqrt(L) * (1-L) * 2` with L clamped to [0, 1].
    public static func weight(luminance: Double) -> Double {
        let l = min(max(luminance, 0), 1)
        return l.squareRoot() * (1 - l) * 2
    }

    /// Multiply centered uniform noise by this, then blur with `sigma`, to get std ≈ 1.
    /// Same closed form as `filmsim.grain.unit_noise_gain` (scipy truncate=4, separable).
    /// The samples themselves stay uniform; Python's `add_grain` draws normal noise.
    public static func unitNoiseGain(sigma: Double) -> Double {
        let stdIn = 1 / 12.0.squareRoot()
        if sigma <= 0 { return 1 / stdIn }
        let lw = Int(4 * sigma + 0.5)
        if lw <= 0 { return 1 / stdIn }
        var weights: [Double] = []
        weights.reserveCapacity(lw * 2 + 1)
        var sum = 0.0
        for i in -lw...lw {
            let x = Double(i) / sigma
            let w = exp(-0.5 * x * x)
            weights.append(w)
            sum += w
        }
        var sumOfSquares = 0.0
        for w in weights {
            let n = w / sum
            sumOfSquares += n * n
        }
        return 1 / (stdIn * sumOfSquares)
    }

    public static func apply(
        to image: CIImage,
        strength: GrainStrength,
        size: GrainSize,
        pixelScale: Double = 1,
        kernel: CIColorKernel
    ) -> CIImage {
        let amp = strength.amplitude
        if amp == 0 { return image }
        let sigma = size.sigma * pixelScale
        let gain = unitNoiseGain(sigma: sigma)
        let pad = CGFloat(max(sigma * 4, 2))
        let expanded = image.extent.insetBy(dx: -pad, dy: -pad)
        guard let random = CIFilter.randomGenerator().outputImage else { return image }
        // Scale uniform [0, 1] noise to mean 0, std ≈ 1 after the blur (ColorMatrixVectors rows).
        var matrix = ColorMatrixVectors(r: [gain, 0, 0], g: [0, 0, 0], b: [0, 0, 0]).ciColorMatrixParameters
        matrix["inputBiasVector"] = CIVector(x: CGFloat(-0.5 * gain), y: 0, z: 0, w: 0)
        let noise =
            random
            .cropped(to: expanded)
            .applyingFilter("CIColorMatrix", parameters: matrix)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: image.extent)
        return kernel.apply(
            extent: image.extent,
            arguments: [image, noise, NSNumber(value: Float(amp))]
        ) ?? image
    }
}

extension GrainStrength {
    public var amplitude: Double {
        switch self {
        case .off: return 0
        case .weak: return 0.025
        case .strong: return 0.05
        }
    }
}

extension GrainSize {
    /// Gaussian sigma in pixels at full resolution.
    public var sigma: Double {
        switch self {
        case .small: return 0.6
        case .large: return 1.1
        }
    }
}

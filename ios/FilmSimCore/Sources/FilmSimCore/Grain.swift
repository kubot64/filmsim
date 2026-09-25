import CoreImage
import Foundation

/// Film grain: luminance-weighted monochrome noise, matching research/filmsim/grain.py.
///
/// The weight is exact. The noise field is uniform noise, blurred, then scaled so its
/// standard deviation matches scipy's `gaussian_filter` followed by `/= std`.
/// Core Image's gaussian is not bit-identical to scipy, so the GPU amplitude is approximate.
public enum Grain {
    public static func amplitude(_ s: GrainStrength) -> Double {
        switch s {
        case .off: return 0
        case .weak: return 0.025
        case .strong: return 0.05
        }
    }

    public static func sigma(_ s: GrainSize) -> Double {
        switch s {
        case .small: return 0.6
        case .large: return 1.1
        }
    }

    /// `sqrt(L) * (1-L) * 2` with L clamped to [0, 1].
    public static func weight(luminance: Double) -> Double {
        let l = min(max(luminance, 0), 1)
        return l.squareRoot() * (1 - l) * 2
    }

    /// Multiply centered uniform noise by this, then blur with `sigma`, to get std ≈ 1.
    /// Mirrors scipy.ndimage.gaussian_filter (truncate=4) applied separably.
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
        kernel: CIKernel
    ) -> CIImage {
        let amp = amplitude(strength)
        if amp == 0 { return image }
        let sigma = sigma(size) * pixelScale
        let gain = unitNoiseGain(sigma: sigma)
        let pad = CGFloat(max(sigma * 4, 2))
        let expanded = image.extent.insetBy(dx: -pad, dy: -pad)
        let noise = CIFilter.randomGenerator().outputImage!
            .cropped(to: expanded)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(gain), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat(-0.5 * gain), y: 0, z: 0, w: 0),
            ])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: image.extent)
        return kernel.apply(
            extent: image.extent,
            roiCallback: { _, rect in rect },
            arguments: [image, noise, NSNumber(value: Float(amp))]
        ) ?? image
    }
}

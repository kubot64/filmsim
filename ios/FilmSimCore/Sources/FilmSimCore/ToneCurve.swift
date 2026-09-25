import CoreImage
import Foundation

/// Highlight / shadow tone. Same eye-tuned curve as research/filmsim/tone.py.
/// The Metal `toneCurve` kernel must stay in lockstep with `evaluate`.
public enum ToneCurve {
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// One display-referred channel in [0, 1]. `highlight` and `shadow` are -2...+4.
    public static func evaluate(_ x: Double, highlight: Double, shadow: Double) -> Double {
        let x = min(max(x, 0), 1)
        var out = x
        if highlight != 0 {
            let w = smoothstep(0.5, 1.0, x)
            let gamma = max(1 - 0.12 * highlight, 0.2)
            out = out * (1 - w) + pow(x, gamma) * w
        }
        if shadow != 0 {
            let w = 1 - smoothstep(0.0, 0.5, x)
            let gamma = max(1 + 0.12 * shadow, 0.2)
            out = out * (1 - w) + pow(x, gamma) * w
        }
        return min(max(out, 0), 1)
    }

    public static func apply(
        to image: CIImage,
        highlight: Double,
        shadow: Double,
        kernel: CIColorKernel
    ) -> CIImage {
        if highlight == 0, shadow == 0 { return image }
        return kernel.apply(
            extent: image.extent,
            arguments: [image, NSNumber(value: Float(highlight)), NSNumber(value: Float(shadow))]
        ) ?? image
    }
}

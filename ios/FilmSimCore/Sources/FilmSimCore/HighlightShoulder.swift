import CoreImage
import Foundation

/// Fixed lift of the LUT output's highlights toward X-series camera JPEGs.
/// Same as `x_series_shoulder` in research/filmsim/tone.py (docs/DESIGN.md, #16).
/// The Metal `xSeriesShoulder` kernel must stay in lockstep with `evaluate`.
///
/// Luma above `knee` is blended toward luma^`gamma` with a smoothstep, and RGB is
/// scaled by the luma ratio, so hue and saturation stay put. Below the knee and at
/// 1.0 nothing changes.
public enum HighlightShoulder {
    public static let knee = 0.6
    public static let gamma = 0.5
    /// BT.709 luma of the LUT output code values.
    public static let luma: SIMD3<Double> = [0.2126, 0.7152, 0.0722]

    /// One display-referred pixel in [0, 1].
    public static func evaluate(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let rgb = rgb.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
        let y = (rgb * luma).sum()
        guard y > 1e-6 else { return rgb }
        let w = ToneCurve.smoothstep(knee, 1.0, y)
        let lifted = y * (1 - w) + pow(y, gamma) * w
        return (rgb * (lifted / y)).clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
    }

    public static func apply(to image: CIImage, kernel: CIColorKernel) -> CIImage {
        kernel.apply(extent: image.extent, arguments: [image]) ?? image
    }
}

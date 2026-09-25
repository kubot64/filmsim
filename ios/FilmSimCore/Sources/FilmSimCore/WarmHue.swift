import CoreImage
import Foundation

/// Fixed rotation of warm hues after the Provia LUT, toward X-series camera JPEGs.
/// Same as `x_series_warm_hue` in research/filmsim/hue.py (docs/DESIGN.md, #11).
/// The Metal `xSeriesWarmHue` kernel must stay in lockstep with `evaluate`.
///
/// Works in BT.709 Y'CbCr of the display-referred codes: Y' and the chroma length stay
/// put, the Cb/Cr angle turns by `degrees` at `center`, fading to 0 at `center ± width`
/// with a raised cosine. Classic Chrome is not rotated.
public enum WarmHue {
    public static let degrees = -7.0
    public static let center = 140.0
    public static let width = 80.0

    public static func applies(to simulation: FilmSimulation) -> Bool { simulation == .provia }

    private static let kr = 0.2126, kb = 0.0722
    private static let kg = 1 - kr - kb
    private static let cbScale = 2 * (1 - kb)
    private static let crScale = 2 * (1 - kr)

    /// One display-referred pixel in [0, 1].
    public static func evaluate(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let c = rgb.clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
        let y = kr * c.x + kg * c.y + kb * c.z
        let cb = (c.z - y) / cbScale
        let cr = (c.x - y) / crScale
        let h = atan2(cr, cb) * 180 / .pi
        var d = (h - center + 180).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        d -= 180
        guard abs(d) < width else { return c }
        let t = degrees * .pi / 180 * 0.5 * (1 + cos(.pi * d / width))
        let cb2 = cb * cos(t) - cr * sin(t)
        let cr2 = cb * sin(t) + cr * cos(t)
        let r = y + crScale * cr2
        let b = y + cbScale * cb2
        let g = (y - kr * r - kb * b) / kg
        return SIMD3(r, g, b).clamped(lowerBound: SIMD3(repeating: 0), upperBound: SIMD3(repeating: 1))
    }

    public static func apply(to image: CIImage, kernel: CIColorKernel) -> CIImage {
        kernel.apply(extent: image.extent, arguments: [image]) ?? image
    }
}

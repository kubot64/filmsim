import CoreImage
import CoreImage.CIFilterBuiltins

/// Highlight / shadow tone. Placeholder: same eye-tuned shape as research/filmsim/tone.py.
public enum ToneCurve {
    public static func apply(to image: CIImage, highlight: Double, shadow: Double) -> CIImage {
        if highlight == 0, shadow == 0 { return image }
        // TODO: port tone.py exactly (smoothstep-blended gamma). For now approximate with CIToneCurve.
        let f = CIFilter.toneCurve()
        f.inputImage = image
        let hGamma = max(1 - 0.12 * highlight, 0.2)
        let sGamma = max(1 + 0.12 * shadow, 0.2)
        f.point0 = CGPoint(x: 0, y: 0)
        f.point1 = CGPoint(x: 0.25, y: pow(0.25, sGamma))
        f.point2 = CGPoint(x: 0.5, y: 0.5)
        f.point3 = CGPoint(x: 0.75, y: pow(0.75, hGamma))
        f.point4 = CGPoint(x: 1, y: 1)
        return f.outputImage ?? image
    }
}

import CoreGraphics
import CoreImage
import ImageIO

/// 24mm main-camera frame cropped to a 35mm-equivalent 3:2.
public enum SensorCrop {
    public static let wideEquivalentMM = 24.0
    public static let targetEquivalentMM = 35.0
    public static var widthFraction: Double { wideEquivalentMM / targetEquivalentMM }

    /// Centered 3:2 crop. Width is `widthFraction` of the sensor unless that
    /// 3:2 rect would stick out, in which case it shrinks to fit.
    public static func rect35mmThreeByTwo(in extent: CGRect) -> CGRect {
        let fraction = CGFloat(widthFraction)
        var w = extent.width * fraction
        var h = w * 2 / 3
        if h > extent.height {
            h = extent.height
            w = min(extent.width, h * 3 / 2)
        }
        if w > extent.width {
            w = extent.width
            h = min(extent.height, w * 2 / 3)
        }
        return CGRect(x: extent.midX - w / 2, y: extent.midY - h / 2, width: w, height: h)
    }
}

public extension CIImage {
    /// Same framing as `SensorCrop.rect35mmThreeByTwo`, snapped to whole pixels.
    /// `self` must be the sensor-native buffer (wide side along x). A portrait
    /// buffer would apply 24/35 to the short side and land near 47mm instead of 35mm.
    func cropped35mmThreeByTwo() -> CIImage {
        let pixels = SensorCrop.rect35mmThreeByTwo(in: extent).integral.intersection(extent)
        guard pixels.width >= 2, pixels.height >= 2 else { return self }
        return cropped(to: pixels)
    }

    /// Crop in sensor orientation, then apply the shot orientation.
    func cropped35mmThreeByTwo(shot orientation: CGImagePropertyOrientation) -> CIImage {
        cropped35mmThreeByTwo().oriented(orientation)
    }
}

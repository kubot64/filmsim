import CoreGraphics
import CoreImage
import ImageIO

/// 24mm main-camera frame cropped to a `FocalLength`-equivalent 3:2.
public enum SensorCrop {
    public static let wideEquivalentMM = 24.0

    /// Share of the sensor's long side kept for `focalLength`. 1 at 24mm.
    public static func widthFraction(_ focalLength: FocalLength) -> Double {
        min(1, wideEquivalentMM / focalLength.millimeters)
    }

    /// Centered 3:2 crop. Width is `widthFraction` of the sensor unless that
    /// 3:2 rect would stick out, in which case it shrinks to fit.
    public static func rectThreeByTwo(in extent: CGRect, focalLength: FocalLength) -> CGRect {
        let fraction = CGFloat(widthFraction(focalLength))
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

extension CIImage {
    /// Same framing as `SensorCrop.rectThreeByTwo`, snapped to whole pixels.
    /// `self` must be the sensor-native buffer (wide side along x). A portrait
    /// buffer would apply 24/35 to the short side and land near 47mm instead of 35mm.
    public func croppedThreeByTwo(focalLength: FocalLength) -> CIImage {
        let pixels = SensorCrop.rectThreeByTwo(in: extent, focalLength: focalLength).integral.intersection(extent)
        guard pixels.width >= 2, pixels.height >= 2 else { return self }
        return cropped(to: pixels)
    }

    /// Crop in sensor orientation, then apply the shot orientation.
    public func croppedThreeByTwo(focalLength: FocalLength, shot orientation: CGImagePropertyOrientation) -> CIImage {
        croppedThreeByTwo(focalLength: focalLength).oriented(orientation)
    }
}

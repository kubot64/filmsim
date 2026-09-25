import CoreGraphics
import CoreImage

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

    /// Extra zoom on top of aspect-fill into a 3:2 view, so the visible region
    /// matches `rect35mmThreeByTwo`. `videoAspect` is width/height of the preview
    /// stream; it is assumed to cover the full sensor.
    public static func previewZoom(videoAspectWidthOverHeight videoAspect: Double) -> Double {
        let viewAspect = 3.0 / 2.0
        let filledWidthFraction = videoAspect <= viewAspect ? 1.0 : viewAspect / videoAspect
        let sensor = CGRect(x: 0, y: 0, width: CGFloat(videoAspect), height: 1)
        let crop = rect35mmThreeByTwo(in: sensor)
        return filledWidthFraction / Double(crop.width / sensor.width)
    }
}

public extension CIImage {
    /// Same framing as `SensorCrop.rect35mmThreeByTwo`, snapped to whole pixels.
    func cropped35mmThreeByTwo() -> CIImage {
        let pixels = SensorCrop.rect35mmThreeByTwo(in: extent).integral.intersection(extent)
        guard pixels.width >= 2, pixels.height >= 2 else { return self }
        return cropped(to: pixels)
    }
}

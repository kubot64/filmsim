import CoreGraphics
import CoreImage

/// Maps between the portrait camera preview and the capture device's point of interest.
///
/// The preview shows the focal-length crop (`SensorCrop.rectThreeByTwo`) of the sensor-native
/// frame, turned 90° clockwise into a portrait 2:3 view: the saved 3:2 turned upright.
/// Device points are normalized to the sensor-native frame, (0,0) top-left and (1,1) bottom-right,
/// as `AVCaptureDevice.focusPointOfInterest` expects. View points are normalized to the preview,
/// (0,0) top-left.
public enum PreviewGeometry {
    /// 4:3 sensor, used until the active format's aspect is known.
    public static let defaultSensorAspect = 4.0 / 3.0

    /// Normalized crop in the sensor-native frame. `sensorAspect` is the unrotated width/height.
    public static func crop(sensorAspect: Double, focalLength: FocalLength) -> CGRect {
        let aspect = sensorAspect > 0 ? sensorAspect : defaultSensorAspect
        let sensor = CGRect(x: 0, y: 0, width: aspect, height: 1)
        let r = SensorCrop.rectThreeByTwo(in: sensor, focalLength: focalLength)
        return CGRect(x: r.minX / aspect, y: r.minY, width: r.width / aspect, height: r.height)
    }

    /// The 2:3 preview aspect-filled into `bounds`, centred. It can stick out of `bounds`.
    public static func imageRect(in bounds: CGRect) -> CGRect {
        let s = max(bounds.width / 2, bounds.height / 3)
        return CGRect(x: bounds.midX - s, y: bounds.midY - s * 1.5, width: s * 2, height: s * 3)
    }

    /// Focus point for a tap at `location` (view coordinates), normalized to the preview.
    /// A tap near the edge moves in until a `frameSize` square around it is fully inside `bounds`,
    /// so the drawn frame and the point being measured stay the same. Nil when nothing is shown.
    public static func focusViewPoint(forTap location: CGPoint, in bounds: CGRect, frameSize: CGSize) -> CGPoint? {
        let image = imageRect(in: bounds)
        let area = image.intersection(bounds).insetBy(dx: frameSize.width / 2, dy: frameSize.height / 2)
        guard !area.isNull, image.width > 0, image.height > 0 else { return nil }
        let x = min(max(location.x, area.minX), area.maxX)
        let y = min(max(location.y, area.minY), area.maxY)
        return CGPoint(x: (x - image.minX) / image.width, y: (y - image.minY) / image.height)
    }

    /// A 90° clockwise turn: the view's top edge is the crop's left edge, its left edge the crop's bottom.
    public static func devicePoint(fromView p: CGPoint, crop c: CGRect) -> CGPoint {
        CGPoint(x: c.minX + p.y * c.width, y: c.minY + (1 - p.x) * c.height)
    }
}

public extension CIImage {
    /// A sensor-native camera frame as the live preview shows it: the focal-length crop,
    /// turned 90° clockwise, aspect-filled and centred in `size`, and cut to `size` at the origin
    /// (a fractional scale otherwise leaves the extent a pixel larger).
    /// Must agree with `PreviewGeometry.devicePoint(fromView:crop:)`, which maps taps back.
    func livePreviewFrame(focalLength: FocalLength, filling size: CGSize) -> CIImage {
        var image = croppedThreeByTwo(focalLength: focalLength).oriented(.right)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return image.transformed(by: CGAffineTransform(
            translationX: (size.width - image.extent.width) / 2,
            y: (size.height - image.extent.height) / 2
        )).cropped(to: CGRect(origin: .zero, size: size))
    }
}

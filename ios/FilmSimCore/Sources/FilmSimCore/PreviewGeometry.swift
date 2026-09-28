import CoreGraphics

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

    /// A 90° clockwise turn: the view's top edge is the crop's left edge, its left edge the crop's bottom.
    public static func devicePoint(fromView p: CGPoint, crop c: CGRect) -> CGPoint {
        CGPoint(x: c.minX + p.y * c.width, y: c.minY + (1 - p.x) * c.height)
    }

    /// `d` moved inside `crop`, keeping `margin` (a fraction of the crop) from its edges so a frame
    /// drawn around the point stays on screen. Points already inside come back unchanged.
    public static func clamped(_ d: CGPoint, into c: CGRect, margin: CGFloat = 0.05) -> CGPoint {
        let inner = c.insetBy(dx: c.width * margin, dy: c.height * margin)
        return CGPoint(x: min(max(d.x, inner.minX), inner.maxX), y: min(max(d.y, inner.minY), inner.maxY))
    }

    /// Inverse of `devicePoint(fromView:crop:)`. Outside 0...1 when the point is outside the crop.
    public static func viewPoint(fromDevice d: CGPoint, crop c: CGRect) -> CGPoint {
        CGPoint(x: 1 - (d.y - c.minY) / c.height, y: (d.x - c.minX) / c.width)
    }
}

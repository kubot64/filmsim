import CoreGraphics

/// Extra zoom so a portrait 2:3 preview matches the 35mm crop after a 90° rotation.
public enum PreviewFraming {
    /// 4:3 sensor, used until the active format's aspect is known.
    public static var defaultZoom: CGFloat {
        CGFloat(SensorCrop.targetEquivalentMM / SensorCrop.wideEquivalentMM)
    }

    /// `sensorAspect` is the unrotated format width/height. The preview layer shows that
    /// frame rotated 90° into a 2:3 view, which is the saved 3:2 crop turned upright.
    public static func zoom(sensorAspectWidthOverHeight sensorAspect: Double) -> Double {
        guard sensorAspect > 0 else { return Double(defaultZoom) }
        let displayedAspect = 1 / sensorAspect
        let viewAspect = 2.0 / 3.0
        let filledWidthFraction = displayedAspect <= viewAspect ? 1.0 : viewAspect / displayedAspect
        let sensor = CGRect(x: 0, y: 0, width: CGFloat(sensorAspect), height: 1)
        let crop = SensorCrop.rect35mmThreeByTwo(in: sensor)
        let visibleWidthFraction = Double(crop.height / max(sensor.height, 1))
        guard visibleWidthFraction > 0 else { return Double(defaultZoom) }
        return filledWidthFraction / visibleWidthFraction
    }
}

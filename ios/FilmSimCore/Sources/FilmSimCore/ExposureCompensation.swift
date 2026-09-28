import Foundation

/// Capture-time exposure compensation, set on the camera before the shot.
/// Unlike `Recipe.exposureEV` it changes the light reaching the sensor, so a minus value
/// keeps highlights that would otherwise clip (OPEN_QUESTIONS "ハイライトの余裕").
/// 1/3 EV steps up to ±3, like the X100 dial.
public enum ExposureCompensation {
    /// UserDefaults entry, shared by the camera and settings screens. Kept across launches.
    public static let storageKey = "captureExposureBias"
    public static let stepsPerEV = 3
    public static let limitEV: Float = 3

    /// The stored bias, or 0 when nothing is stored yet.
    public static func stored(in defaults: UserDefaults = .standard) -> Float {
        Float(defaults.double(forKey: storageKey))
    }

    public static func store(_ value: Float, in defaults: UserDefaults = .standard) {
        defaults.set(Double(value), forKey: storageKey)
    }

    /// Moves `current` by `steps` thirds of a stop, snapped to the 1/3 grid and clamped to
    /// ±3 and to the device's `minExposureTargetBias...maxExposureTargetBias`.
    public static func stepped(_ current: Float, by steps: Int, deviceRange: ClosedRange<Float>) -> Float {
        let thirds = Int((current * Float(stepsPerEV)).rounded()) + steps
        let ev = Float(thirds) / Float(stepsPerEV)
        let lower = max(-limitEV, deviceRange.lowerBound)
        let upper = min(limitEV, deviceRange.upperBound)
        return min(max(ev, lower), upper)
    }

    /// Every stop on the camera screen's dial (#56), in thirds: −9 (−3 EV) … +9 (+3 EV).
    public static let dialThirds: [Int] = Array(-Int(limitEV) * stepsPerEV...Int(limitEV) * stepsPerEV)

    /// `ev` as a whole number of thirds, the dial's position for it.
    public static func thirds(_ ev: Float) -> Int {
        Int((ev * Float(stepsPerEV)).rounded())
    }

    public static func ev(thirds: Int) -> Float {
        Float(thirds) / Float(stepsPerEV)
    }

    /// "±0", "+⅓", "−⅔", "+1", "−1⅓".
    public static func label(_ ev: Float) -> String {
        let thirds = Int((ev * Float(stepsPerEV)).rounded())
        if thirds == 0 { return "±0" }
        let sign = thirds > 0 ? "+" : "−"
        let whole = abs(thirds) / stepsPerEV
        let fraction = ["", "⅓", "⅔"][abs(thirds) % stepsPerEV]
        return sign + (whole > 0 ? "\(whole)" : "") + fraction
    }
}

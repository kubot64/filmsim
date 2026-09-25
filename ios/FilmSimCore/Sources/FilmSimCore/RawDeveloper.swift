import CoreImage
import Foundation
import ImageIO

/// Wraps CIRAWFilter so that it hands back near scene-linear data:
/// no boost, no local tone mapping, values above 1.0 kept, Apple's demosaic / noise reduction / lens correction kept.
public enum RawDeveloper {
    public struct Options: Sendable {
        public var luminanceNoiseReduction: Float = 0.3   // Apple default is stronger than Fujifilm; tune (OPEN_QUESTIONS)
        public var colorNoiseReduction: Float = 0.5
        public var sharpness: Float = 0.0                  // sharpening is done later, if at all
        /// 1 is full resolution. Previews pass a smaller value so demosaic matches the display size.
        public var scaleFactor: Float = 1
        public init() {}
    }

    /// Returns a linear CIImage in the filter's working space (Display P3 linear on iOS).
    ///
    /// The 35mm crop runs on the sensor-native buffer. `CIRAWFilter` otherwise
    /// applies the shot orientation first, and a portrait frame would crop the
    /// short side (about 47mm instead of 35mm).
    public static func developLinear(rawData: Data, options: Options = Options()) -> CIImage? {
        guard let filter = CIRAWFilter(imageData: rawData, identifierHint: nil) else { return nil }
        let shot = filter.orientation
        filter.orientation = .up
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        filter.isGamutMappingEnabled = true
        filter.isLensCorrectionEnabled = true
        filter.luminanceNoiseReductionAmount = options.luminanceNoiseReduction
        filter.colorNoiseReductionAmount = options.colorNoiseReduction
        filter.sharpnessAmount = options.sharpness
        filter.scaleFactor = options.scaleFactor
        // Keep values above 1.0. With 0 the filter clips at 1.0 and throws away up to ~1.3 stops of
        // real red/blue data around lights, which then render as flat light grey (#24).
        filter.extendedDynamicRangeAmount = 1
        guard let sensor = filter.outputImage else { return nil }
        return sensor.cropped35mmThreeByTwo(shot: shot)
    }
}

import CoreImage
import Foundation

/// Wraps CIRAWFilter so that it hands back near scene-linear data:
/// no boost, no local tone mapping, Apple's demosaic / noise reduction / lens correction kept.
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
    public static func developLinear(rawData: Data, options: Options = Options()) -> CIImage? {
        guard let filter = CIRAWFilter(imageData: rawData, identifierHint: nil) else { return nil }
        filter.boostAmount = 0
        filter.boostShadowAmount = 0
        filter.localToneMapAmount = 0
        filter.isGamutMappingEnabled = true
        filter.isLensCorrectionEnabled = true
        filter.luminanceNoiseReductionAmount = options.luminanceNoiseReduction
        filter.colorNoiseReductionAmount = options.colorNoiseReduction
        filter.sharpnessAmount = options.sharpness
        filter.scaleFactor = options.scaleFactor
        filter.extendedDynamicRangeAmount = 0
        return filter.outputImage
    }
}

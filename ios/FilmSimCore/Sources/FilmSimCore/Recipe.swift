import Foundation

public enum FilmSimulation: String, CaseIterable, Codable, Sendable {
    case provia
    case classicChrome

    /// Resource name (without ".cube") of the official LUT in the app bundle.
    /// Files come from the GFX ETERNA 55 LUT package via scripts/fetch_luts.sh.
    public var lutFileName: String {
        switch self {
        case .provia: return "FLog2_to_PROVIA_65grid_V.1.00"
        case .classicChrome: return "FLog2_to_CLASSIC-CHROME_65grid_V.1.00"
        }
    }
}

public enum GrainStrength: String, CaseIterable, Codable, Sendable { case off, weak, strong }
public enum GrainSize: String, CaseIterable, Codable, Sendable { case small, large }

/// Mirrors `filmsim.pipeline.Recipe` in research/. Keep the two in sync.
public struct Recipe: Codable, Equatable, Sendable {
    public var filmSimulation: FilmSimulation = .provia
    public var exposureEV: Double = 0
    public var wbShiftR: Double = 0   // -9...+9
    public var wbShiftB: Double = 0   // -9...+9
    public var highlight: Double = 0  // -2...+4
    public var shadow: Double = 0     // -2...+4
    public var grainStrength: GrainStrength = .off
    public var grainSize: GrainSize = .small

    public init() {}

    /// Linear RGB multipliers for the WB shift. Step size mirrors research/filmsim/pipeline.py.
    public var wbGains: SIMD3<Double> {
        let step = 0.03
        return [1 + step * wbShiftR, 1, 1 + step * wbShiftB]
    }
}

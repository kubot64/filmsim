import Foundation

public enum FilmSimulation: String, CaseIterable, Codable, Sendable {
    case provia
    case classicChrome
    case portra400vc

    /// Generic names, not the film or simulation the look is based on: those are trademarks
    /// (Fujifilm, Kodak). Case names and raw values keep the source so stored recipes still decode.
    public var displayName: String {
        switch self {
        case .provia: return "ナチュラル"
        case .classicChrome: return "ネガフィルム"
        case .portra400vc: return "アメリカ"
        }
    }

    /// Resource name (without ".cube") of the LUT in the app bundle. The Fujifilm files come
    /// from the GFX ETERNA 55 LUT package via scripts/fetch_luts.sh; Portra 400VC is baked from
    /// Kodak's datasheet by research/scripts/bake_negative.py and committed.
    public var lutFileName: String {
        switch self {
        case .provia: return "FLog2_to_PROVIA_65grid_V.1.00"
        case .classicChrome: return "FLog2_to_CLASSIC-CHROME_65grid_V.1.00"
        case .portra400vc: return "Portra400VC_65grid"
        }
    }

    /// The X-series highlight shoulder (#16) pulls Fujifilm's GFX LUTs towards X-series JPEGs.
    /// Other looks have their own highlights in the LUT. Mirrors pipeline.FUJIFILM_FILM_SIMS.
    public var usesXSeriesShoulder: Bool {
        switch self {
        case .provia, .classicChrome: return true
        case .portra400vc: return false
        }
    }
}

public enum GrainStrength: String, CaseIterable, Codable, Sendable { case off, weak, strong }
public enum GrainSize: String, CaseIterable, Codable, Sendable { case small, large }

/// Mirrors `filmsim.pipeline.Recipe` in research/. Keep the two in sync.
public struct Recipe: Codable, Equatable, Sendable {
    public var filmSimulation: FilmSimulation = .provia
    /// Name of an imported LUT (`ImportedLUT`) to use instead of `filmSimulation`. Nil for the
    /// built-in looks. When that LUT has been deleted, rendering falls back to `filmSimulation`.
    public var importedLUT: String?
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

import Foundation
import simd

/// D65 RGB spaces used by the pipeline. F-Gamut == BT.2020 primaries.
public struct RGBSpace: Sendable {
    public let name: String
    public let red: SIMD2<Double>
    public let green: SIMD2<Double>
    public let blue: SIMD2<Double>
    public let white: SIMD2<Double>

    public static let d65 = SIMD2(0.31270, 0.32900)
    public static let fGamut = RGBSpace(name: "F-Gamut", red: [0.708, 0.292], green: [0.170, 0.797], blue: [0.131, 0.046], white: d65)
    public static let displayP3 = RGBSpace(name: "Display P3", red: [0.680, 0.320], green: [0.265, 0.690], blue: [0.150, 0.060], white: d65)
    public static let bt709 = RGBSpace(name: "BT.709", red: [0.640, 0.330], green: [0.300, 0.600], blue: [0.150, 0.060], white: d65)

    /// Matrix mapping linear RGB (this space) to XYZ. Columns are R, G, B.
    public var toXYZ: double3x3 {
        func col(_ p: SIMD2<Double>) -> SIMD3<Double> { [p.x, p.y, 1 - p.x - p.y] }
        let m = double3x3(columns: (col(red), col(green), col(blue)))
        let w = SIMD3(white.x / white.y, 1, (1 - white.x - white.y) / white.y)
        let s = m.inverse * w
        return double3x3(columns: (col(red) * s.x, col(green) * s.y, col(blue) * s.z))
    }

    public var fromXYZ: double3x3 { toXYZ.inverse }

    public static func conversion(from src: RGBSpace, to dst: RGBSpace) -> double3x3 {
        dst.fromXYZ * src.toXYZ
    }
}

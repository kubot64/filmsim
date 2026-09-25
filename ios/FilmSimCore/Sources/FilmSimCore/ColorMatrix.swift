import CoreImage
import simd

/// CIColorMatrix vectors for `out = matrix * (rgb * gains)`.
///
/// Measured: `out.r = dot(rgb, inputRVector)`. Each vector is a row of `matrix`
/// (row 0 produces output R), and each component is multiplied by that input
/// channel's gain. `matrix[column, row]` matches `RGBSpace.toXYZ`.
public struct ColorMatrixVectors {
    public var r: SIMD3<Double>
    public var g: SIMD3<Double>
    public var b: SIMD3<Double>

    public init(r: SIMD3<Double>, g: SIMD3<Double>, b: SIMD3<Double>) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var rVector: CIVector { Self.vector(r) }
    public var gVector: CIVector { Self.vector(g) }
    public var bVector: CIVector { Self.vector(b) }

    /// `matrix[column, row]`. Row `i` is `(M_i0 * gx, M_i1 * gy, M_i2 * gz)`.
    public static func contributions(_ matrix: double3x3, gains: SIMD3<Double>) -> ColorMatrixVectors {
        func row(_ i: Int) -> SIMD3<Double> {
            SIMD3(matrix[0, i] * gains.x, matrix[1, i] * gains.y, matrix[2, i] * gains.z)
        }
        return ColorMatrixVectors(r: row(0), g: row(1), b: row(2))
    }

    private static func vector(_ v: SIMD3<Double>) -> CIVector {
        CIVector(x: CGFloat(v.x), y: CGFloat(v.y), z: CGFloat(v.z), w: 0)
    }
}

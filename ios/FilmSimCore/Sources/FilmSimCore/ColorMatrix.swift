import simd

/// CIColorMatrix vectors for `out = matrix * (rgb * gains)`.
///
/// CIColorMatrix computes `out = r*inputRVector + g*inputGVector + b*inputBVector`.
/// Each vector is that input channel's column of `matrix` (rows are R, G, B out),
/// scaled by the per-channel gain. `matrix[column, row]` matches `RGBSpace.toXYZ`.
public enum ColorMatrix {
    public static func contributions(
        _ matrix: double3x3,
        gains: SIMD3<Double>
    ) -> (r: SIMD3<Double>, g: SIMD3<Double>, b: SIMD3<Double>) {
        func column(_ c: Int, gain: Double) -> SIMD3<Double> {
            SIMD3(matrix[c, 0], matrix[c, 1], matrix[c, 2]) * gain
        }
        return (column(0, gain: gains.x), column(1, gain: gains.y), column(2, gain: gains.z))
    }
}

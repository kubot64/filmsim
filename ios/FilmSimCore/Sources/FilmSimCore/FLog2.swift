import Foundation

/// F-Log2 transfer function. Constants from the F-Log2 Data Sheet Ver.1.1.
/// Reference: 18% grey -> 0.391 (10bit 400), 90% -> 0.557 (570).
/// CPU reference implementation; the GPU path is the `flog2Encode` CIColorKernel in the app target.
public enum FLog2 {
    public static let a = 5.555556
    public static let b = 0.064829
    public static let c = 0.245281
    public static let d = 0.384316
    public static let e = 8.799461
    public static let f = 0.092864
    public static let cut1 = 0.000889
    public static let cut2 = 0.100686685370811

    public static func encode(_ x: Double) -> Double {
        x >= cut1 ? c * log10(a * x + b) + d : e * x + f
    }

    public static func decode(_ y: Double) -> Double {
        y >= cut2 ? pow(10, (y - d) / c) / a - b / a : (y - f) / e
    }
}

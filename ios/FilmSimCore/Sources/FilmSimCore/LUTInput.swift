import Foundation
import simd

/// Sony S-Log3 transfer function, from Sony's "Technical Summary for S-Gamut3.Cine/S-Log3 and
/// S-Gamut3/S-Log3". Reference: 0 % -> 95/1023, 18 % grey -> 420/1023, 90 % -> 598/1023.
public enum SLog3 {
    public static func encode(_ x: Double) -> Double {
        x >= 0.01125
            ? (420 + log10((x + 0.01) / (0.18 + 0.01)) * 261.5) / 1023
            : (x * (171.2102946929 - 95) / 0.01125 + 95) / 1023
    }

    public static func decode(_ y: Double) -> Double {
        y >= 171.2102946929 / 1023
            ? pow(10, (y * 1023 - 420) / 261.5) * (0.18 + 0.01) - 0.01
            : (y * 1023 - 95) * 0.01125 / (171.2102946929 - 95)
    }
}

extension RGBSpace {
    public static let sGamut3 = RGBSpace(name: "S-Gamut3", red: [0.730, 0.280], green: [0.140, 0.855], blue: [0.100, -0.050], white: d65)
    public static let sGamut3Cine = RGBSpace(name: "S-Gamut3.Cine", red: [0.766, 0.275], green: [0.225, 0.800], blue: [0.089, -0.087], white: d65)
}

/// What an imported LUT expects as input. The pipeline feeds every LUT F-Log2 / F-Gamut codes,
/// so a LUT made for another log is re-baked at import (`CubeLUT.convertedToFLog2`). Film-look
/// LUTs are far more common for Sony's S-Log3 than for F-Log2.
public enum LUTInput: String, CaseIterable, Sendable {
    case fLog2
    case sLog3SGamut3Cine
    case sLog3SGamut3

    public var displayName: String {
        switch self {
        case .fLog2: return "F-Log2 / F-Gamut"
        case .sLog3SGamut3Cine: return "S-Log3 / S-Gamut3.Cine"
        case .sLog3SGamut3: return "S-Log3 / S-Gamut3"
        }
    }

    /// F-Log2 / F-Gamut code values to this input's code values.
    public func codes(fromFLog2 code: SIMD3<Double>) -> SIMD3<Double> {
        switch self {
        case .fLog2:
            return code
        case .sLog3SGamut3Cine, .sLog3SGamut3:
            let space: RGBSpace = self == .sLog3SGamut3Cine ? .sGamut3Cine : .sGamut3
            let linear = SIMD3(FLog2.decode(code.x), FLog2.decode(code.y), FLog2.decode(code.z))
            let s = RGBSpace.conversion(from: .fGamut, to: space) * linear
            return SIMD3(SLog3.encode(s.x), SLog3.encode(s.y), SLog3.encode(s.z))
        }
    }
}

extension CubeLUT {
    /// Trilinear lookup, `rgb` clamped to [0, 1]. Same interpolation as CIColorCube.
    public func sample(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let n = size
        let p = simd_clamp(rgb, SIMD3(repeating: 0), SIMD3(repeating: 1)) * Double(n - 1)
        let i0 = SIMD3<Int>(Int(min(p.x.rounded(.down), Double(n - 2))),
                            Int(min(p.y.rounded(.down), Double(n - 2))),
                            Int(min(p.z.rounded(.down), Double(n - 2))))
        let f = p - SIMD3<Double>(Double(i0.x), Double(i0.y), Double(i0.z))
        return rgbaData.withUnsafeBytes { buf -> SIMD3<Double> in
            let t = buf.bindMemory(to: Float.self)
            func node(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Double> {
                let i = ((b * n + g) * n + r) * 4
                return SIMD3(Double(t[i]), Double(t[i + 1]), Double(t[i + 2]))
            }
            var out = SIMD3<Double>(repeating: 0)
            for dr in 0...1 { for dg in 0...1 { for db in 0...1 {
                let w = (dr == 1 ? f.x : 1 - f.x) * (dg == 1 ? f.y : 1 - f.y) * (db == 1 ? f.z : 1 - f.z)
                out += w * node(i0.x + dr, i0.y + dg, i0.z + db)
            } } }
            return out
        }
    }

    /// The same look re-baked to take F-Log2 / F-Gamut codes: each node's F-Log2 code is converted
    /// to `input`'s codes and looked up in this LUT. Identity for `.fLog2`.
    public func convertedToFLog2(from input: LUTInput, size newSize: Int = 65) -> CubeLUT {
        guard input != .fLog2 else { return self }
        var floats: [Float] = []
        floats.reserveCapacity(newSize * newSize * newSize * 4)
        let step = 1 / Double(newSize - 1)
        for b in 0..<newSize {
            for g in 0..<newSize {
                for r in 0..<newSize {
                    let code = SIMD3(Double(r), Double(g), Double(b)) * step
                    let out = sample(input.codes(fromFLog2: code))
                    floats.append(contentsOf: [Float(out.x), Float(out.y), Float(out.z), 1])
                }
            }
        }
        return CubeLUT(title: "\(title) (\(input.displayName) -> F-Log2)", size: newSize, floats: floats)
    }

    /// The .cube text `init(text:)` reads back: red fastest, as the file format orders it.
    public var cubeText: String {
        var lines = ["TITLE \"\(title)\"", "LUT_3D_SIZE \(size)"]
        lines.reserveCapacity(size * size * size + 2)
        rgbaData.withUnsafeBytes { buf in
            let t = buf.bindMemory(to: Float.self)
            for i in stride(from: 0, to: t.count, by: 4) {
                lines.append(String(format: "%.6f %.6f %.6f", t[i], t[i + 1], t[i + 2]))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

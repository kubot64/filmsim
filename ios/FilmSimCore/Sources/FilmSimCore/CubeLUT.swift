import Foundation

/// Parsed .cube 3D LUT, laid out for CIColorCubeWithColorSpace (RGBA float, red fastest).
public struct CubeLUT: Sendable {
    public let title: String
    public let size: Int
    public let rgbaData: Data

    /// Imported files come from anywhere, so every limit is checked before memory is spent
    /// and a bad file is an error, never a crash.
    public enum ParseError: Error, Equatable {
        case missingSize
        case badSize(String)
        case badRowCount(expected: Int, got: Int)
        case unsupported1D
        case unsupportedDomain
        case badValue(String)
        case tooLarge
    }

    /// Grids seen in real LUTs are 17, 33, 64 and 65. Past 65 the table only costs memory.
    public static let sizeRange = 2...65
    /// A 65 grid with six decimals is about 8 MB; anything far past that is not a LUT we can use.
    public static let maxFileBytes = 32 * 1024 * 1024
    /// Outputs are colours; real LUTs overshoot 0...1 a little at most.
    static let valueLimit: Float = 16

    /// From RGBA floats already in CIColorCube order (red fastest). Used by `convertedToFLog2`.
    init(title: String, size: Int, floats: [Float]) {
        precondition(floats.count == size * size * size * 4)
        self.title = title
        self.size = size
        self.rgbaData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data)
    }

    /// Size-checked before decoding, for files read from outside the app.
    public init(data: Data) throws {
        guard data.count <= Self.maxFileBytes else { throw ParseError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ParseError.badValue("UTF-8 ではない") }
        try self.init(text: text)
    }

    public init(text: String) throws {
        guard text.utf8.count <= Self.maxFileBytes else { throw ParseError.tooLarge }
        let maxRows = Self.sizeRange.upperBound * Self.sizeRange.upperBound * Self.sizeRange.upperBound
        var title = ""
        var size: Int?
        var floats: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = parts.first else { continue }
            switch keyword {
            case "TITLE":
                title = parts.dropFirst().joined(separator: " ").trimmingCharacters(
                    in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE":
                guard size == nil, parts.count == 2, let n = Int(parts[1]), Self.sizeRange.contains(n) else {
                    throw ParseError.badSize(String(line.prefix(40)))
                }
                size = n
            case "LUT_1D_SIZE": throw ParseError.unsupported1D
            case "DOMAIN_MIN", "DOMAIN_MAX":
                // Only the default domain: a LUT over another input range would read our codes wrong.
                let expected: Float = keyword == "DOMAIN_MIN" ? 0 : 1
                let values = parts.dropFirst().compactMap { Float($0) }
                guard parts.count == 4, values.count == 3, values.allSatisfy({ abs($0 - expected) < 1e-6 }) else {
                    throw ParseError.unsupportedDomain
                }
            case "LUT_3D_INPUT_RANGE":
                // Older Resolve spelling of the domain: "min max" for all three channels.
                let values = parts.dropFirst().compactMap { Float($0) }
                guard parts.count == 3, values.count == 2, abs(values[0]) < 1e-6, abs(values[1] - 1) < 1e-6 else {
                    throw ParseError.unsupportedDomain
                }
            default:
                guard parts.count == 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else {
                    continue
                }
                for v in [r, g, b] where !v.isFinite || abs(v) > Self.valueLimit {
                    throw ParseError.badValue(String(line.prefix(40)))
                }
                let limit = size.map { $0 * $0 * $0 } ?? maxRows
                guard floats.count / 4 < limit else {
                    throw ParseError.badRowCount(expected: limit, got: floats.count / 4 + 1)
                }
                floats.append(contentsOf: [r, g, b, 1.0])
            }
        }
        guard let n = size else { throw ParseError.missingSize }
        let expected = n * n * n
        guard floats.count / 4 == expected else {
            throw ParseError.badRowCount(expected: expected, got: floats.count / 4)
        }
        self.title = String(title.prefix(200))
        self.size = n
        self.rgbaData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Sample the LUT at a grid node (no interpolation). Used by tests.
    public func node(r: Int, g: Int, b: Int) -> (Float, Float, Float) {
        let i = ((b * size + g) * size + r) * 4
        return rgbaData.withUnsafeBytes { buf in
            let p = buf.bindMemory(to: Float.self)
            return (p[i], p[i + 1], p[i + 2])
        }
    }
}

extension CubeLUT.ParseError {
    /// Japanese reason shown when an import is refused.
    public var message: String {
        switch self {
        case .missingSize: return "3D LUT（.cube）ではありません"
        case .badSize: return "LUT の大きさが対応範囲（\(CubeLUT.sizeRange.lowerBound)〜\(CubeLUT.sizeRange.upperBound)）の外か、読めません"
        case .badRowCount(let expected, let got): return "数値の行の数が合いません（\(expected) 行のはずが \(got) 行）"
        case .unsupported1D: return "1D LUT には対応していません"
        case .unsupportedDomain: return "入力の範囲（DOMAIN）が 0〜1 以外の LUT には対応していません"
        case .badValue: return "数値として読めない値か、大きすぎる値が入っています"
        case .tooLarge: return "ファイルが大きすぎます"
        }
    }
}

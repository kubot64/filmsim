import Foundation

/// Parsed .cube 3D LUT, laid out for CIColorCubeWithColorSpace (RGBA float, red fastest).
public struct CubeLUT: Sendable {
    public let title: String
    public let size: Int
    public let rgbaData: Data

    public enum ParseError: Error { case missingSize, badRowCount(expected: Int, got: Int), unsupported1D }

    public init(contentsOf url: URL) throws {
        try self.init(text: String(contentsOf: url, encoding: .utf8))
    }

    public init(text: String) throws {
        var title = ""
        var size: Int?
        var floats: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            switch parts[0] {
            case "TITLE": title = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            case "LUT_3D_SIZE": size = Int(parts[1])
            case "LUT_1D_SIZE": throw ParseError.unsupported1D
            case "DOMAIN_MIN", "DOMAIN_MAX": continue
            default:
                guard parts.count == 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { continue }
                floats.append(contentsOf: [r, g, b, 1.0])
            }
        }
        guard let n = size else { throw ParseError.missingSize }
        let expected = n * n * n
        guard floats.count / 4 == expected else { throw ParseError.badRowCount(expected: expected, got: floats.count / 4) }
        self.title = title
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

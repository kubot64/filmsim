import Foundation

/// 35mm-equivalent focal lengths cut from the 24mm main camera. The whole DNG is kept, so a
/// shot can be re-developed at another focal length. Longer than 35mm drops too far below 5MP.
public enum FocalLength: Int, CaseIterable, Codable, Sendable {
    case mm24 = 24
    case mm28 = 28
    case mm35 = 35

    /// UserDefaults entry, shared by the camera, develop and settings screens. Kept across launches.
    public static let storageKey = "focalLength"
    public static let `default`: FocalLength = .mm35

    public var millimeters: Double { Double(rawValue) }
    public var displayName: String { "\(rawValue)mm" }

    /// The next choice, wrapping 35 → 24. The camera screen's button steps through them.
    public var next: FocalLength {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The stored choice, or the default when nothing (or an unknown value) is stored.
    public static func stored(in defaults: UserDefaults = .standard) -> FocalLength {
        FocalLength(rawValue: defaults.integer(forKey: storageKey)) ?? .default
    }
}

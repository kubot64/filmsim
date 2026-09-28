import Foundation

/// App-level UserDefaults keys that are not part of FilmSimCore.
enum AppPreferences {
    /// Whether develop-and-save also writes the original DNG to the photo library.
    static let saveDNGKey = "saveDNG"
    /// Whether the camera screen shows the development status line (RAW size, save result).
    static let showStatusKey = "showCameraStatus"
}

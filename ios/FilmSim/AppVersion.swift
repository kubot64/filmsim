import Foundation

/// Which commit this build came from (`BuildInfo`, generated at build time).
/// "+" marks a build with uncommitted changes.
enum AppVersion {
    static var label: String {
        "\(BuildInfo.commit)\(BuildInfo.isDirty ? "+" : "") (\(BuildInfo.commitDate))"
    }

    /// Written into the HEIC's TIFF Software tag.
    static var software: String { "Irocam \(label)" }
}

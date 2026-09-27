import Foundation

/// The last-used recipe, shared by the camera and develop screens through one
/// UserDefaults entry (`@AppStorage(Recipe.storageKey)`), not a shared object (#8).
extension Recipe {
    public static let storageKey = "lastRecipe"

    public var encoded: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// The stored recipe, or the default when nothing is stored yet or the data no longer
    /// decodes (for example after a field is added to `Recipe`).
    public static func decoded(from data: Data) -> Recipe {
        (try? JSONDecoder().decode(Recipe.self, from: data)) ?? Recipe()
    }

    /// One line for the camera screen, under the film simulation menu: only the settings
    /// that differ from the default. Empty when there are none.
    public var adjustmentSummary: String {
        let d = Recipe()
        var parts: [String] = []
        if exposureEV != d.exposureEV { parts.append(String(format: "EV %+.2f", exposureEV)) }
        if wbShiftR != d.wbShiftR || wbShiftB != d.wbShiftB {
            parts.append(String(format: "WB R%+.0f B%+.0f", wbShiftR, wbShiftB))
        }
        if highlight != d.highlight { parts.append(String(format: "H %+.0f", highlight)) }
        if shadow != d.shadow { parts.append(String(format: "S %+.0f", shadow)) }
        if grainStrength != d.grainStrength { parts.append("Grain \(grainStrength.rawValue) \(grainSize.rawValue)") }
        return parts.joined(separator: " · ")
    }
}

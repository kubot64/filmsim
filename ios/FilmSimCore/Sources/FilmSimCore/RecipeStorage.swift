import Foundation

/// JSON for a `Recipe`. `storageKey` held the single last-used recipe before recipes were saved
/// by name (#54); `RecipeBook` reads it once to migrate.
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
}

import Foundation

/// A recipe the user keeps under a name (#54). The camera's recipe strip lists these.
public struct SavedRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var recipe: Recipe
    public var isHidden: Bool
    /// Set on the plain recipe made when a LUT is imported, to the LUT's name. It lets deleting and
    /// renaming the LUT act on that recipe only, not on another recipe switched to the same LUT.
    public var createdForLUT: String?

    public init(id: UUID = UUID(), name: String, recipe: Recipe, isHidden: Bool = false, createdForLUT: String? = nil) {
        self.id = id
        self.name = name
        self.recipe = recipe
        self.isHidden = isHidden
        self.createdForLUT = createdForLUT
    }
}

/// The saved recipes, in the order the strip shows them, and the one in use.
/// Stored as JSON under `storageKey`.
public struct RecipeBook: Codable, Equatable, Sendable {
    public static let storageKey = "recipeBook"

    public private(set) var recipes: [SavedRecipe]
    public private(set) var selectedID: UUID

    /// One plain recipe per built-in film simulation, named like it. `migrating` is the recipe the
    /// app used before recipes were saved (`Recipe.storageKey`): it is selected, either as the
    /// matching plain recipe or, when it has adjustments or an imported LUT, as a recipe of its own.
    public static func initial(migrating last: Recipe? = nil) -> RecipeBook {
        let recipes = FilmSimulation.allCases.map { sim in
            var recipe = Recipe()
            recipe.filmSimulation = sim
            return SavedRecipe(name: sim.displayName, recipe: recipe)
        }
        var book = RecipeBook(recipes: recipes, selectedID: recipes[0].id)
        guard let last else { return book }
        if let plain = recipes.first(where: { $0.recipe == last }) {
            book.selectedID = plain.id
        } else {
            let kept = SavedRecipe(name: "以前の設定", recipe: last)
            book.recipes.append(kept)
            book.selectedID = kept.id
        }
        return book
    }

    /// The book stored in `data`, or a fresh one (migrating `last`) when nothing decodes.
    public static func decoded(from data: Data, migrating last: Recipe? = nil) -> RecipeBook {
        if let book = try? JSONDecoder().decode(RecipeBook.self, from: data), !book.recipes.isEmpty {
            return book
        }
        return initial(migrating: last)
    }

    public var encoded: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// The recipes the strip shows.
    public var visible: [SavedRecipe] { recipes.filter { !$0.isHidden } }

    /// The recipe in use. Falls back to the first visible one if the selection went missing.
    public var selected: SavedRecipe {
        recipes.first { $0.id == selectedID } ?? visible.first ?? recipes[0]
    }

    public mutating func select(_ id: UUID) {
        guard recipes.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Replaces the settings of the recipe in use, keeping its name.
    public mutating func updateSelected(_ recipe: Recipe) {
        guard let i = recipes.firstIndex(where: { $0.id == selected.id }) else { return }
        recipes[i].recipe = recipe
    }

    /// A plain recipe for an imported LUT, unless one was already made for it or already uses it.
    public mutating func addImportedLUT(named lutName: String, displayName: String) {
        guard !recipes.contains(where: { $0.createdForLUT == lutName || $0.recipe.importedLUT == lutName }) else {
            return
        }
        recipes.append(SavedRecipe(name: displayName, recipe: Self.plain(lutName), createdForLUT: lutName))
    }

    /// Adds recipes for LUTs that were imported before recipes were saved (or that have none for
    /// another reason), so every imported LUT can be chosen. Run at launch.
    public mutating func addMissingImportedLUTs(_ luts: [(name: String, displayName: String)]) {
        for lut in luts { addImportedLUT(named: lut.name, displayName: lut.displayName) }
    }

    /// The LUT's display name changed: the recipe made for it follows, unless the user has
    /// named that recipe something else.
    public mutating func renameImportedLUT(
        named lutName: String, from oldDisplayName: String, to newDisplayName: String
    ) {
        for i in recipes.indices where recipes[i].createdForLUT == lutName && recipes[i].name == oldDisplayName {
            recipes[i].name = newDisplayName
        }
    }

    /// After an imported LUT is deleted: the untouched recipe made for it goes. Every other recipe
    /// that used it stays and drops the LUT, rendering with its built-in simulation as before
    /// (`ResolvedLook`), so nothing the user set up is lost. The selection moves to the first
    /// visible recipe if its recipe went.
    public mutating func removeImportedLUT(named lutName: String) {
        recipes.removeAll { $0.createdForLUT == lutName && $0.recipe == Self.plain(lutName) }
        for i in recipes.indices where recipes[i].recipe.importedLUT == lutName {
            recipes[i].recipe.importedLUT = nil
            recipes[i].createdForLUT = nil
        }
        if recipes.isEmpty { self = .initial() }
        if !recipes.contains(where: { $0.id == selectedID }) {
            selectedID = (visible.first ?? recipes[0]).id
        }
    }

    private static func plain(_ lutName: String) -> Recipe {
        var recipe = Recipe()
        recipe.importedLUT = lutName
        return recipe
    }
}

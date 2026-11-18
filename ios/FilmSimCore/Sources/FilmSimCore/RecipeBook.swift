import Foundation

/// A recipe the user keeps under a name (#54). The camera's recipe strip lists these.
public struct SavedRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var recipe: Recipe
    public var isHidden: Bool
    /// Set on the plain recipe made when a LUT is imported, to the LUT's name. It lets deleting and
    /// renaming the LUT act on that recipe only, not on another recipe switched to the same LUT.
    /// Cleared once the recipe switches to another look or the LUT is deleted.
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

    /// One plain recipe per built-in film simulation in `available` (the ones this build ships a
    /// LUT for), named like it. `migrating` is the recipe the app used before recipes were saved
    /// (`Recipe.storageKey`): it is selected, either as the matching plain recipe or, when it has
    /// adjustments or an imported LUT, as a recipe of its own.
    public static func initial(
        available: [FilmSimulation] = FilmSimulation.allCases, migrating last: Recipe? = nil
    ) -> RecipeBook {
        let looks = available.isEmpty ? FilmSimulation.allCases : available
        let recipes = looks.map { SavedRecipe(name: $0.displayName, recipe: Self.plain($0)) }
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

    /// Replaces the settings of the recipe in use, keeping its name. A recipe made for a LUT that
    /// switches to another look stops being that LUT's recipe for good (#88), so the LUT gets a
    /// plain recipe again at launch and renaming the LUT no longer renames this one.
    public mutating func updateSelected(_ recipe: Recipe) {
        guard let i = recipes.firstIndex(where: { $0.id == selected.id }) else { return }
        recipes[i].recipe = recipe
        if let lut = recipes[i].createdForLUT, recipe.importedLUT != lut {
            recipes[i].createdForLUT = nil
        }
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
    /// that used it stays and drops the LUT, rendering with its built-in look as before
    /// (`ResolvedLook`), so nothing the user set up is lost. That look is one of `available`, as
    /// `moveOffMissingLooks` keeps it.
    public mutating func removeImportedLUT(named lutName: String, available: [FilmSimulation]) {
        recipes.removeAll { $0.createdForLUT == lutName && Self.isPlain($0.recipe, lut: lutName) }
        for i in recipes.indices where recipes[i].recipe.importedLUT == lutName {
            recipes[i].recipe.importedLUT = nil
            recipes[i].createdForLUT = nil
        }
        moveOffMissingLooks(available: available)
    }

    /// Moves every recipe off the built-in looks this build doesn't ship. `available` are the ones
    /// it does, the first being where moved recipes go. The App Store build has no Fujifilm LUTs
    /// (ADR 0010): the untouched plain recipe of a missing look goes, and any other recipe on a
    /// missing look moves, keeping its adjustments. A recipe on an imported LUT moves too, since
    /// it renders its built-in look whenever the LUT can't be read. Does nothing when every look,
    /// or none, is available. Run at launch; deleting a LUT runs it as well.
    public mutating func moveOffMissingLooks(available: [FilmSimulation]) {
        let missing = Set(FilmSimulation.allCases).subtracting(available)
        if let destination = available.first, !missing.isEmpty {
            recipes.removeAll { saved in
                let sim = saved.recipe.filmSimulation
                return missing.contains(sim) && saved.createdForLUT == nil && saved.name == sim.displayName
                    && saved.recipe == Self.plain(sim)
            }
            for i in recipes.indices where missing.contains(recipes[i].recipe.filmSimulation) {
                recipes[i].recipe.filmSimulation = destination
            }
        }
        if recipes.isEmpty { self = .initial(available: available) }
        if !recipes.contains(where: { $0.id == selectedID }) {
            selectedID = (visible.first ?? recipes[0]).id
        }
    }

    private static func plain(_ simulation: FilmSimulation) -> Recipe {
        var recipe = Recipe()
        recipe.filmSimulation = simulation
        return recipe
    }

    private static func plain(_ lutName: String) -> Recipe {
        var recipe = Recipe()
        recipe.importedLUT = lutName
        return recipe
    }

    /// Whether `recipe` is the plain recipe for the LUT, whatever built-in look it falls back to
    /// (`moveOffMissingLooks` may have moved that look).
    private static func isPlain(_ recipe: Recipe, lut lutName: String) -> Bool {
        var r = recipe
        r.filmSimulation = Recipe().filmSimulation
        return r == plain(lutName)
    }
}

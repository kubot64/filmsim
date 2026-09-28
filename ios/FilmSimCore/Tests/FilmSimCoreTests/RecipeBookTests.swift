import XCTest
@testable import FilmSimCore

final class RecipeBookTests: XCTestCase {
    func testInitialHasOnePlainRecipePerFilmSimulation() {
        let book = RecipeBook.initial()
        XCTAssertEqual(book.recipes.map(\.name), FilmSimulation.allCases.map(\.displayName))
        XCTAssertEqual(book.recipes.map(\.recipe.filmSimulation), FilmSimulation.allCases)
        for saved in book.recipes {
            var plain = Recipe()
            plain.filmSimulation = saved.recipe.filmSimulation
            XCTAssertEqual(saved.recipe, plain)
        }
        XCTAssertEqual(book.selected.id, book.recipes[0].id)
    }

    /// A plain last-used recipe selects the matching built-in one; nothing is added.
    func testMigratingAPlainRecipeSelectsItsSimulation() {
        var last = Recipe()
        last.filmSimulation = .classicChrome
        let book = RecipeBook.initial(migrating: last)
        XCTAssertEqual(book.recipes.count, FilmSimulation.allCases.count)
        XCTAssertEqual(book.selected.recipe, last)
    }

    /// Adjustments the user had made are kept as their own recipe and selected.
    func testMigratingAnAdjustedRecipeKeepsIt() {
        var last = Recipe()
        last.filmSimulation = .classicChrome
        last.grainStrength = .weak
        last.shadow = 1
        let book = RecipeBook.initial(migrating: last)
        XCTAssertEqual(book.recipes.count, FilmSimulation.allCases.count + 1)
        XCTAssertEqual(book.selected.recipe, last)
        XCTAssertEqual(book.selected.name, "以前の設定")
    }

    func testRoundTrip() {
        var book = RecipeBook.initial()
        book.addImportedLUT(named: "FLog2_to_ETERNA", displayName: "Eterna")
        book.select(book.recipes.last!.id)
        XCTAssertEqual(RecipeBook.decoded(from: book.encoded), book)
    }

    func testBrokenDataStartsFreshAndMigrates() {
        var last = Recipe()
        last.filmSimulation = .portra400vc
        let book = RecipeBook.decoded(from: Data("not json".utf8), migrating: last)
        XCTAssertEqual(book.selected.recipe, last)
    }

    func testSelectIgnoresAnUnknownID() {
        var book = RecipeBook.initial()
        let before = book.selectedID
        book.select(UUID())
        XCTAssertEqual(book.selectedID, before)
    }

    func testUpdateSelectedKeepsTheName() {
        var book = RecipeBook.initial()
        book.select(book.recipes[1].id)
        var changed = book.selected.recipe
        changed.highlight = 2
        book.updateSelected(changed)
        XCTAssertEqual(book.recipes[1].recipe.highlight, 2)
        XCTAssertEqual(book.recipes[1].name, FilmSimulation.allCases[1].displayName)
        XCTAssertEqual(book.recipes[0].recipe.highlight, 0)
    }

    func testImportingALUTAddsOnePlainRecipe() {
        var book = RecipeBook.initial()
        book.addImportedLUT(named: "Kodak", displayName: "コダック")
        book.addImportedLUT(named: "Kodak", displayName: "コダック")
        let added = book.recipes.filter { $0.recipe.importedLUT == "Kodak" }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.name, "コダック")
    }

    func testDeletingALUTRemovesItsPlainRecipeAndMovesTheSelection() {
        var book = RecipeBook.initial()
        book.addImportedLUT(named: "Kodak", displayName: "コダック")
        book.select(book.recipes.last!.id)
        book.removeImportedLUT(named: "Kodak")
        XCTAssertFalse(book.recipes.contains { $0.recipe.importedLUT == "Kodak" })
        XCTAssertEqual(book.selected.id, book.recipes[0].id)
    }

    /// A recipe the user adjusted on top of the LUT stays; it renders with its built-in simulation.
    func testDeletingALUTKeepsAnAdjustedRecipe() {
        var book = RecipeBook.initial()
        book.addImportedLUT(named: "Kodak", displayName: "コダック")
        book.select(book.recipes.last!.id)
        var adjusted = book.selected.recipe
        adjusted.grainStrength = .strong
        book.updateSelected(adjusted)
        book.removeImportedLUT(named: "Kodak")
        XCTAssertEqual(book.selected.recipe, adjusted)
    }
}

final class ShotLogTests: XCTestCase {
    func testRoundTripKeepsTheRecipeAsItWas() {
        var recipe = Recipe()
        recipe.filmSimulation = .classicChrome
        recipe.grainStrength = .weak
        let shot = ShotRecord(
            date: Date(timeIntervalSince1970: 1_790_000_000), heicAssetID: "A/L0/001", dngAssetID: "B/L0/001",
            recipeName: "散歩用", recipe: recipe, focalLength: .mm28
        )
        var log = ShotLog()
        log.append(shot)
        XCTAssertEqual(ShotLog.decoded(from: log.encoded), log)
    }

    func testNewestFirst() {
        var log = ShotLog()
        for i in 0..<3 {
            log.append(ShotRecord(
                date: Date(timeIntervalSince1970: Double(i)), heicAssetID: "\(i)", dngAssetID: nil,
                recipeName: "x", recipe: Recipe(), focalLength: .mm35
            ))
        }
        XCTAssertEqual(log.newestFirst.map(\.heicAssetID), ["2", "1", "0"])
    }

    func testMissingOrBrokenDataIsEmpty() {
        XCTAssertEqual(ShotLog.decoded(from: Data()), ShotLog())
        XCTAssertEqual(ShotLog.decoded(from: Data("{".utf8)), ShotLog())
    }
}

import XCTest

@testable import FilmSimCore

final class LookTests: XCTestCase {
    private func tinyLUT(_ title: String) throws -> CubeLUT {
        let rows = (0..<8).map { i in "\(i & 1) \((i >> 1) & 1) \((i >> 2) & 1)" }
        return try CubeLUT(text: "TITLE \"\(title)\"\nLUT_3D_SIZE 2\n" + rows.joined(separator: "\n"))
    }

    func testDisplayNamesAvoidTrademarks() {
        XCTAssertEqual(FilmSimulation.provia.displayName, "ナチュラル")
        XCTAssertEqual(FilmSimulation.classicChrome.displayName, "ネガフィルム")
        XCTAssertEqual(FilmSimulation.portra400vc.displayName, "アメリカ")
    }

    /// A recipe saved before `importedLUT` existed has every other key and no "importedLUT".
    /// (A JSON missing other keys falls back to the default recipe; that is RecipeStorageTests.)
    func testRecipesStoredBeforeImportsStillDecode() throws {
        var before = Recipe()
        before.filmSimulation = .classicChrome
        before.exposureEV = 0.5
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: before.encoded) as? [String: Any])
        json.removeValue(forKey: "importedLUT")
        let old = try JSONSerialization.data(withJSONObject: json)
        let r = Recipe.decoded(from: old)
        XCTAssertEqual(r.exposureEV, 0.5)
        XCTAssertEqual(r.filmSimulation, .classicChrome)
        XCTAssertNil(r.importedLUT)
        XCTAssertEqual(r.look, .builtIn(.classicChrome))
    }

    func testChoosingAnImportKeepsTheBuiltInToFallBackTo() {
        var r = Recipe()
        r.look = .builtIn(.portra400vc)
        r.look = .imported("My LUT")
        XCTAssertEqual(r.look, .imported("My LUT"))
        XCTAssertEqual(r.filmSimulation, .portra400vc)
        XCTAssertEqual(Recipe.decoded(from: r.encoded).look, .imported("My LUT"))
        r.look = .builtIn(.provia)
        XCTAssertNil(r.importedLUT)
    }

    func testOfficialFujifilmImportsGetTheXSeriesFixes() {
        XCTAssertTrue(ImportedLUT.usesXSeriesShoulder(name: "FLog2_to_ETERNA_65grid_V.1.00"))
        XCTAssertTrue(ImportedLUT.appliesWarmHue(name: "FLog2_to_PROVIA_65grid_V.1.00"))
        XCTAssertFalse(ImportedLUT.appliesWarmHue(name: "FLog2_to_ETERNA_65grid_V.1.00"))
        XCTAssertFalse(ImportedLUT.usesXSeriesShoulder(name: "My Film Look"))
    }

    func testImportNamesStayOneFileInTheFolder() {
        XCTAssertEqual(
            ImportedLUT.name(forFileName: "FLog2_to_ETERNA_65grid_V.1.00.cube"), "FLog2_to_ETERNA_65grid_V.1.00")
        XCTAssertEqual(ImportedLUT.name(forFileName: "../evil.CUBE"), "_evil")
        XCTAssertEqual(ImportedLUT.name(forFileName: ".cube"), "LUT")
    }

    func testResolvePrefersTheImportAndFallsBackWhenItIsGone() throws {
        let builtIn = [FilmSimulation.provia: try tinyLUT("provia"), .portra400vc: try tinyLUT("portra")]
        var r = Recipe()
        r.look = .builtIn(.portra400vc)
        r.look = .imported("FLog2_to_PROVIA_x")

        let withImport = ResolvedLook.resolve(r, builtIn: builtIn, imported: ["FLog2_to_PROVIA_x": try tinyLUT("imp")])
        XCTAssertEqual(withImport?.lut.title, "imp")
        XCTAssertEqual(withImport?.xSeriesShoulder, true)
        XCTAssertEqual(withImport?.warmHue, true)

        let deleted = ResolvedLook.resolve(r, builtIn: builtIn, imported: [:])
        XCTAssertEqual(deleted?.lut.title, "portra")
        XCTAssertEqual(deleted?.xSeriesShoulder, false)
        XCTAssertEqual(r.effectiveLook(importedNames: []), .builtIn(.portra400vc))
        XCTAssertEqual(r.effectiveLook(importedNames: ["FLog2_to_PROVIA_x"]), .imported("FLog2_to_PROVIA_x"))
    }
}

final class LUTDisplayNamesTests: XCTestCase {
    func testRenameIsRememberedAndBlankGoesBackToTheFileName() {
        var names = LUTDisplayNames()
        XCTAssertEqual(names.displayName(for: "FLog2_to_PROVIA_65grid_V.1.00"), "FLog2_to_PROVIA_65grid_V.1.00")
        names.rename("FLog2_to_PROVIA_65grid_V.1.00", to: "  いつもの  ")
        XCTAssertEqual(names.displayName(for: "FLog2_to_PROVIA_65grid_V.1.00"), "いつもの")

        let restored = LUTDisplayNames.decoded(from: names.encoded)
        XCTAssertEqual(restored.displayName(for: "FLog2_to_PROVIA_65grid_V.1.00"), "いつもの")

        names.rename("FLog2_to_PROVIA_65grid_V.1.00", to: " ")
        XCTAssertEqual(names.displayName(for: "FLog2_to_PROVIA_65grid_V.1.00"), "FLog2_to_PROVIA_65grid_V.1.00")
        XCTAssertTrue(names.names.isEmpty)
    }

    func testRemoveForgetsTheName() {
        var names = LUTDisplayNames()
        names.rename("a", to: "A")
        names.remove("a")
        XCTAssertEqual(names.displayName(for: "a"), "a")
    }

    func testBrokenDataStartsEmpty() {
        XCTAssertEqual(LUTDisplayNames.decoded(from: Data("x".utf8)), LUTDisplayNames())
    }
}
